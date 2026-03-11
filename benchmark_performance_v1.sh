#!/bin/bash

echo "🚀 Benchmarking Meteor Performance V1 vs Redis..."

# Start Meteor Performance V1 server
echo "📡 Starting Meteor Performance V1 server..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
    cd /tmp/meteor-perf-v1
    pkill -f meteor-performance-v1 2>/dev/null || true
    ./meteor-performance-v1 --port 6395 --shards 32 --enable-logging &
    sleep 3
    echo 'Meteor Performance V1 server started on port 6395'
" &

# Start Redis server
echo "📡 Starting Redis server..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
    pkill -f redis-server 2>/dev/null || true
    redis-server --port 6380 --daemonize yes
    echo 'Redis server started on port 6380'
" &

# Wait for servers to start
sleep 5

echo ""
echo "🧪 Running performance benchmarks..."
echo ""

# Test configuration
CLIENTS=50
REQUESTS=100000
DATA_SIZE=1000

echo "📊 Test Configuration:"
echo "  Clients: $CLIENTS"
echo "  Requests: $REQUESTS"
echo "  Data Size: $DATA_SIZE bytes"
echo ""

# Create results directory
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="mkdir -p /tmp/benchmark_results_perf_v1"

# Benchmark Meteor Performance V1
echo "🔥 Benchmarking Meteor Performance V1..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
    cd /tmp/benchmark_results_perf_v1
    
    echo 'SET operations - Meteor Performance V1:'
    redis-benchmark -h localhost -p 6395 -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t set -q --csv > meteor_v1_set.csv
    
    echo 'GET operations - Meteor Performance V1:'
    redis-benchmark -h localhost -p 6395 -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t get -q --csv > meteor_v1_get.csv
    
    echo 'PING operations - Meteor Performance V1:'
    redis-benchmark -h localhost -p 6395 -c $CLIENTS -n $REQUESTS -t ping -q --csv > meteor_v1_ping.csv
    
    echo 'INCR operations - Meteor Performance V1:'
    redis-benchmark -h localhost -p 6395 -c $CLIENTS -n $REQUESTS -t incr -q --csv > meteor_v1_incr.csv
    
    echo 'Mixed operations - Meteor Performance V1:'
    redis-benchmark -h localhost -p 6395 -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t set,get,incr,lpush,lpop -q --csv > meteor_v1_mixed.csv
"

# Benchmark Redis
echo "🔥 Benchmarking Redis..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
    cd /tmp/benchmark_results_perf_v1
    
    echo 'SET operations - Redis:'
    redis-benchmark -h localhost -p 6380 -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t set -q --csv > redis_set.csv
    
    echo 'GET operations - Redis:'
    redis-benchmark -h localhost -p 6380 -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t get -q --csv > redis_get.csv
    
    echo 'PING operations - Redis:'
    redis-benchmark -h localhost -p 6380 -c $CLIENTS -n $REQUESTS -t ping -q --csv > redis_ping.csv
    
    echo 'INCR operations - Redis:'
    redis-benchmark -h localhost -p 6380 -c $CLIENTS -n $REQUESTS -t incr -q --csv > redis_incr.csv
    
    echo 'Mixed operations - Redis:'
    redis-benchmark -h localhost -p 6380 -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t set,get,incr,lpush,lpop -q --csv > redis_mixed.csv
"

# Generate performance comparison report
echo "📈 Generating performance comparison report..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
    cd /tmp/benchmark_results_perf_v1
    
    echo '# Meteor Performance V1 vs Redis Benchmark Results' > performance_comparison.md
    echo '' >> performance_comparison.md
    echo '## Test Configuration' >> performance_comparison.md
    echo '- Clients: $CLIENTS' >> performance_comparison.md
    echo '- Requests: $REQUESTS' >> performance_comparison.md
    echo '- Data Size: $DATA_SIZE bytes' >> performance_comparison.md
    echo '- Date: $(date)' >> performance_comparison.md
    echo '' >> performance_comparison.md
    
    echo '## Performance Results' >> performance_comparison.md
    echo '' >> performance_comparison.md
    
    # Parse and compare results
    for operation in set get ping incr mixed; do
        echo \"### \${operation^^} Operations\" >> performance_comparison.md
        echo '' >> performance_comparison.md
        
        if [[ -f \"meteor_v1_\${operation}.csv\" && -f \"redis_\${operation}.csv\" ]]; then
            meteor_rps=\$(tail -1 \"meteor_v1_\${operation}.csv\" | cut -d',' -f2 | tr -d '\"')
            redis_rps=\$(tail -1 \"redis_\${operation}.csv\" | cut -d',' -f2 | tr -d '\"')
            
            echo \"- **Meteor Performance V1**: \${meteor_rps} req/sec\" >> performance_comparison.md
            echo \"- **Redis**: \${redis_rps} req/sec\" >> performance_comparison.md
            
            # Calculate improvement ratio
            if [[ \"\$redis_rps\" != \"0\" ]]; then
                ratio=\$(echo \"scale=2; \$meteor_rps / \$redis_rps\" | bc -l)
                if (( \$(echo \"\$ratio > 1\" | bc -l) )); then
                    improvement=\$(echo \"scale=1; (\$ratio - 1) * 100\" | bc -l)
                    echo \"- **Performance**: \${improvement}% faster than Redis\" >> performance_comparison.md
                else
                    degradation=\$(echo \"scale=1; (1 - \$ratio) * 100\" | bc -l)
                    echo \"- **Performance**: \${degradation}% slower than Redis\" >> performance_comparison.md
                fi
            fi
        fi
        echo '' >> performance_comparison.md
    done
    
    echo '## Summary' >> performance_comparison.md
    echo 'Performance V1 includes:' >> performance_comparison.md
    echo '- ✅ Robust Network I/O with error handling and retries' >> performance_comparison.md
    echo '- ✅ Enhanced socket configuration with proper timeouts' >> performance_comparison.md
    echo '- ✅ Improved send/receive operations with backoff strategies' >> performance_comparison.md
    echo '- ✅ All original features intact (SSD tiering, intelligent caching, etc.)' >> performance_comparison.md
    echo '' >> performance_comparison.md
    
    cat performance_comparison.md
"

# Download results
echo "📥 Downloading benchmark results..."
gcloud compute scp mcache-ssd-tiering-lssd:/tmp/benchmark_results_perf_v1/* ./benchmark_results_perf_v1/ --zone=asia-southeast1-a --project=<your-gcp-project-id> --recurse 2>/dev/null || true

# Stop servers
echo "🛑 Stopping servers..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
    pkill -f meteor-performance-v1 2>/dev/null || true
    pkill -f redis-server 2>/dev/null || true
    echo 'Servers stopped'
"

echo ""
echo "✅ Benchmark completed!"
echo "📁 Results saved to: ./benchmark_results_perf_v1/"
echo ""
echo "🎯 Next steps:"
echo "1. Review performance comparison report"
echo "2. If performance improved, proceed to next optimization"
echo "3. If performance degraded, investigate and fix issues" 