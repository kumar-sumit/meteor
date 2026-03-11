#!/bin/bash

echo "🚀 METEOR COMMERCIAL LRU+TTL - PERFORMANCE BENCHMARK"
echo "Fixed Version: TTL Deadlock Resolved"
echo ""

# Configuration
SERVER_CONFIG="12C:4S:2GB"
echo "Server Config: $SERVER_CONFIG"
echo "Benchmark: 50 clients, 12 threads, pipeline=10, 30s test"
echo ""

# Upload and run on VM
echo "Uploading script to VM..."
gcloud compute scp benchmark_ttl_fixed.sh memtier-benchmarking:/mnt/externalDisk/meteor/ \
  --zone="asia-southeast1-a" --tunnel-through-iap --project="<your-gcp-project-id>" \
  --quiet 2>/dev/null || echo "Upload may have timed out, continuing..."

echo ""
echo "Running benchmark on VM..."

# Run benchmark
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor && 
    echo '🚀 Starting TTL Fixed Server for Benchmark' && 
    pkill -f meteor 2>/dev/null; sleep 2 && 
    ./meteor_commercial_lru_ttl_fixed -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &>/dev/null & 
    SERVER_PID=\$! && 
    sleep 5 && 
    echo 'Server PID:' \$SERVER_PID && 
    echo '' && 
    echo '📊 Running Performance Test...' && 
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis --clients=50 --threads=12 --pipeline=10 --data-size=64 --key-pattern=R:R --ratio=1:3 --test-time=30 --hide-histogram 2>/dev/null | grep -E 'Totals|GET|SET|Throughput|p50|p99' && 
    echo '' && 
    kill \$SERVER_PID 2>/dev/null && 
    echo '✅ Benchmark completed!'"

echo ""
echo "Benchmark script completed."













