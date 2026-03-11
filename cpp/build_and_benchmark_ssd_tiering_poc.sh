#!/bin/bash

# **SSD-TIERING-POC VM: Phase 6 Step 1 Build and Benchmark Script**
# Tests both 16c/32s and 16c/16s configurations with 1GB memory

set -e

echo "🚀 PHASE 6 STEP 1: SSD-TIERING-POC COMPREHENSIVE BENCHMARK"
echo "=========================================================="

# Build the server
echo "🔨 Building Phase 6 Step 1 AVX-512 server..."
g++ -std=c++17 -O3 -march=native -mavx512f -mavx512vl -mavx512bw -DHAS_LINUX_EPOLL -pthread \
    phase6_server.cpp -o meteor_phase6_ssd_poc

echo "✅ Build completed successfully!"

# Function to run benchmark
run_benchmark() {
    local cores=$1
    local shards=$2
    local memory=$3
    local config_name=$4
    
    echo ""
    echo "🔥 TESTING CONFIGURATION: $config_name"
    echo "Cores: $cores, Shards: $shards, Memory: ${memory}MB"
    echo "================================================="
    
    # Kill any existing server
    pkill -f meteor_phase6_ssd_poc || true
    sleep 2
    
    # Start server in background
    echo "🚀 Starting server: $config_name"
    ./meteor_phase6_ssd_poc -h 127.0.0.1 -p 6379 -c $cores -s $shards -m $memory -l > ${config_name}_server.log 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 5
    
    echo "📊 Running memtier-benchmark for $config_name..."
    
    # High-intensity memtier benchmark
    memtier_benchmark -h 127.0.0.1 -p 6379 \
        -t 8 -c 25 -n 50000 \
        --ratio=1:1 --pipeline=50 \
        --key-pattern=R:R --key-minimum=1 --key-maximum=1000000 \
        --print-percentiles=50,90,95,99,99.9 > ${config_name}_memtier_results.txt
    
    echo "📊 Running redis-benchmark for $config_name..."
    
    # Redis benchmark
    redis-benchmark -h 127.0.0.1 -p 6379 \
        -t set,get -n 200000 -c 100 -P 50 > ${config_name}_redis_results.txt 2>&1 || true
    
    # Get server stats
    sleep 2
    echo "📈 Server performance summary for $config_name:"
    tail -20 ${config_name}_server.log
    
    # Kill server
    kill $SERVER_PID || true
    sleep 2
    
    echo "✅ $config_name benchmark completed!"
}

# Test Configuration 1: 16 cores, 32 shards, 1GB
run_benchmark 16 32 1024 "16C_32S_1GB"

# Test Configuration 2: 16 cores, 16 shards, 1GB  
run_benchmark 16 16 1024 "16C_16S_1GB"

echo ""
echo "🏆 ALL BENCHMARKS COMPLETED!"
echo "=============================="

echo "📊 RESULTS SUMMARY:"
echo "=================="

echo ""
echo "🔥 16 CORES / 32 SHARDS / 1GB RESULTS:"
echo "--------------------------------------"
echo "Memtier Results:"
grep -A 5 -B 5 "Totals" 16C_32S_1GB_memtier_results.txt || echo "Memtier results not found"
echo ""
echo "Redis-benchmark Results:"
grep "requests per second" 16C_32S_1GB_redis_results.txt || echo "Redis results not found"

echo ""
echo "🔥 16 CORES / 16 SHARDS / 1GB RESULTS:"
echo "--------------------------------------"
echo "Memtier Results:"
grep -A 5 -B 5 "Totals" 16C_16S_1GB_memtier_results.txt || echo "Memtier results not found"
echo ""
echo "Redis-benchmark Results:"
grep "requests per second" 16C_16S_1GB_redis_results.txt || echo "Redis results not found"

echo ""
echo "🎯 COMPARATIVE ANALYSIS:"
echo "========================"

# Extract RPS from both configurations
RPS_32S=$(grep "Totals" 16C_32S_1GB_memtier_results.txt | awk '{print $2}' | head -1 || echo "N/A")
RPS_16S=$(grep "Totals" 16C_16S_1GB_memtier_results.txt | awk '{print $2}' | head -1 || echo "N/A")

echo "32 Shards RPS: $RPS_32S"
echo "16 Shards RPS: $RPS_16S"

if [[ "$RPS_32S" != "N/A" && "$RPS_16S" != "N/A" ]]; then
    echo "Performance difference: $(echo "scale=2; $RPS_32S / $RPS_16S" | bc)x"
fi

echo ""
echo "📁 All detailed results saved to:"
echo "- 16C_32S_1GB_*.txt (32 shards configuration)"
echo "- 16C_16S_1GB_*.txt (16 shards configuration)"
echo ""
echo "🚀 PHASE 6 STEP 1 SSD-TIERING-POC BENCHMARKS COMPLETE! 🚀"