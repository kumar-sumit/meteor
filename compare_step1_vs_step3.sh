#!/bin/bash
# Performance Comparison: Step 1 Enhanced vs Step 3 Migration

echo "🔬 Performance Comparison: Step 1 Enhanced vs Step 3 Migration"
echo "=============================================================="

cd ~/meteor

# Kill any existing servers
pkill -f meteor_phase5 2>/dev/null || true
sleep 3

# Test configurations
CORES=16
SHARDS=16
PORT=6379
TEST_TIME=60  # Longer test for more accurate results
CLIENTS=10    # More clients to test cross-core scenarios
THREADS=4

echo "📋 Test Configuration:"
echo "   Cores: $CORES"
echo "   Shards: $SHARDS" 
echo "   Test Duration: ${TEST_TIME}s"
echo "   Clients: $CLIENTS"
echo "   Threads: $THREADS"
echo ""

# Function to run benchmark and extract key metrics
run_benchmark() {
    local version=$1
    local description=$2
    
    echo "🚀 Testing $description..."
    
    # Start server
    nohup ./$version -c $CORES -s $SHARDS -p $PORT > server_${version}.log 2>&1 &
    local server_pid=$!
    sleep 5
    
    # Check if server started successfully
    if ! kill -0 $server_pid 2>/dev/null; then
        echo "❌ Server failed to start"
        return 1
    fi
    
    # Run benchmark
    memtier_benchmark -s localhost -p $PORT -c $CLIENTS -t $THREADS \
        --ratio=1:1 --test-time=$TEST_TIME -d 512 --hide-histogram \
        > benchmark_${version}.log 2>&1
    
    # Kill server
    kill $server_pid 2>/dev/null || true
    sleep 2
    
    # Extract metrics
    local total_ops=$(grep "Totals" benchmark_${version}.log | awk '{print $2}')
    local avg_latency=$(grep "Totals" benchmark_${version}.log | awk '{print $5}')
    local p99_latency=$(grep "Totals" benchmark_${version}.log | awk '{print $7}')
    local throughput=$(grep "Totals" benchmark_${version}.log | awk '{print $9}')
    
    echo "   📊 Results:"
    echo "      Total Ops/sec: $total_ops"
    echo "      Avg Latency: $avg_latency ms"
    echo "      P99 Latency: $p99_latency ms" 
    echo "      Throughput: $throughput KB/sec"
    echo ""
    
    # Store results for comparison
    echo "$version,$total_ops,$avg_latency,$p99_latency,$throughput" >> comparison_results.csv
}

# Initialize results file
echo "Version,Ops_per_sec,Avg_Latency_ms,P99_Latency_ms,Throughput_KB_sec" > comparison_results.csv

# Test Step 1 Enhanced (Direct Processing)
if [ -f "meteor_phase5_step1_enhanced" ]; then
    run_benchmark "meteor_phase5_step1_enhanced" "Step 1 Enhanced (Direct Processing)"
else
    echo "❌ meteor_phase5_step1_enhanced not found"
fi

# Test Step 3 Migration (Connection Migration)  
if [ -f "meteor_phase5_step3_migration" ]; then
    run_benchmark "meteor_phase5_step3_migration" "Step 3 Migration (Connection Migration)"
else
    echo "❌ meteor_phase5_step3_migration not found"
fi

echo "📊 PERFORMANCE COMPARISON SUMMARY"
echo "=================================="

if [ -f "comparison_results.csv" ]; then
    echo ""
    cat comparison_results.csv | column -t -s ','
    echo ""
    
    # Calculate performance differences
    if [ $(wc -l < comparison_results.csv) -eq 3 ]; then
        step1_ops=$(sed -n '2p' comparison_results.csv | cut -d',' -f2)
        step3_ops=$(sed -n '3p' comparison_results.csv | cut -d',' -f2)
        
        step1_latency=$(sed -n '2p' comparison_results.csv | cut -d',' -f3)
        step3_latency=$(sed -n '3p' comparison_results.csv | cut -d',' -f3)
        
        if [ ! -z "$step1_ops" ] && [ ! -z "$step3_ops" ]; then
            improvement=$(echo "scale=1; ($step3_ops - $step1_ops) * 100 / $step1_ops" | bc -l 2>/dev/null || echo "N/A")
            echo "🏆 Performance Difference:"
            echo "   Throughput: Step 3 vs Step 1 = ${improvement}% improvement"
            
            if (( $(echo "$step3_ops > $step1_ops" | bc -l 2>/dev/null || echo 0) )); then
                echo "   🥇 Winner: Step 3 Migration (Connection Migration)"
            else
                echo "   🥇 Winner: Step 1 Enhanced (Direct Processing)"
            fi
        fi
    fi
fi

echo ""
echo "📋 Detailed logs available:"
echo "   Server logs: server_*.log"
echo "   Benchmark logs: benchmark_*.log"
echo "   Results: comparison_results.csv"