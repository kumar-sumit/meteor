#!/bin/bash

# **SSD-TIERING-POC VM: Simplified Phase 6 Step 1 Benchmark Script**
# Uses pre-compiled binary from memtier-benchmarking VM

set -e

echo "🚀 PHASE 6 STEP 1: SSD-TIERING-POC SIMPLIFIED BENCHMARK"
echo "========================================================"

# Function to run benchmark with redis-benchmark only
run_redis_benchmark() {
    local cores=$1
    local shards=$2
    local memory=$3
    local config_name=$4
    local port=$5
    
    echo ""
    echo "🔥 TESTING CONFIGURATION: $config_name"
    echo "Cores: $cores, Shards: $shards, Memory: ${memory}MB, Port: $port"
    echo "================================================================="
    
    # Kill any existing server on this port
    pkill -f "meteor_phase6.*$port" || true
    sleep 2
    
    # Check if binary exists
    if [[ ! -f "./meteor_phase6_ssd_poc" ]]; then
        echo "❌ Binary not found. Please copy from memtier-benchmarking VM first."
        return 1
    fi
    
    # Start server in background
    echo "🚀 Starting server: $config_name on port $port"
    ./meteor_phase6_ssd_poc -h 127.0.0.1 -p $port -c $cores -s $shards -m $memory -l > ${config_name}_server.log 2>&1 &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 8
    
    echo "📊 Running redis-benchmark for $config_name..."
    
    # High-intensity redis benchmark - SET operations
    echo "🔥 Testing SET operations..."
    redis-benchmark -h 127.0.0.1 -p $port \
        -t set -n 500000 -c 200 -P 100 \
        --csv > ${config_name}_redis_set_results.csv 2>&1 || true
    
    # High-intensity redis benchmark - GET operations  
    echo "🔥 Testing GET operations..."
    redis-benchmark -h 127.0.0.1 -p $port \
        -t get -n 500000 -c 200 -P 100 \
        --csv > ${config_name}_redis_get_results.csv 2>&1 || true
    
    # Mixed SET/GET benchmark
    echo "🔥 Testing mixed SET/GET operations..."
    redis-benchmark -h 127.0.0.1 -p $port \
        -t set,get -n 300000 -c 150 -P 50 \
        > ${config_name}_redis_mixed_results.txt 2>&1 || true
    
    # Get server stats
    sleep 3
    echo "📈 Server performance summary for $config_name:"
    echo "Last 30 lines of server log:"
    tail -30 ${config_name}_server.log || echo "No server log found"
    
    # Kill server
    kill $SERVER_PID 2>/dev/null || true
    pkill -f "meteor_phase6.*$port" || true
    sleep 3
    
    echo "✅ $config_name benchmark completed!"
}

# Copy binary from memtier-benchmarking VM if not exists
if [[ ! -f "./meteor_phase6_ssd_poc" ]]; then
    echo "📦 Binary not found. You need to copy it manually:"
    echo "gcloud compute scp --zone 'asia-southeast1-a' 'memtier-benchmarking':~/meteor/meteor_phase6_step1_avx512_numa 'mcache-ssd-tiering-poc':~/meteor_phase6_ssd_poc --tunnel-through-iap --project '<your-gcp-project-id>'"
    echo ""
    echo "Or build locally and copy..."
    exit 1
fi

# Make binary executable
chmod +x ./meteor_phase6_ssd_poc

# Test Configuration 1: 16 cores, 32 shards, 1GB
run_redis_benchmark 16 32 1024 "16C_32S_1GB" 6379

# Test Configuration 2: 16 cores, 16 shards, 1GB  
run_redis_benchmark 16 16 1024 "16C_16S_1GB" 6380

echo ""
echo "🏆 ALL BENCHMARKS COMPLETED!"
echo "=============================="

echo "📊 RESULTS SUMMARY:"
echo "=================="

echo ""
echo "🔥 16 CORES / 32 SHARDS / 1GB RESULTS:"
echo "--------------------------------------"
echo "SET Results:"
cat 16C_32S_1GB_redis_set_results.csv 2>/dev/null || echo "SET results not found"
echo "GET Results:"
cat 16C_32S_1GB_redis_get_results.csv 2>/dev/null || echo "GET results not found"
echo "Mixed Results:"
grep "requests per second" 16C_32S_1GB_redis_mixed_results.txt 2>/dev/null || echo "Mixed results not found"

echo ""
echo "🔥 16 CORES / 16 SHARDS / 1GB RESULTS:"
echo "--------------------------------------"
echo "SET Results:"
cat 16C_16S_1GB_redis_set_results.csv 2>/dev/null || echo "SET results not found"
echo "GET Results:"
cat 16C_16S_1GB_redis_get_results.csv 2>/dev/null || echo "GET results not found"
echo "Mixed Results:"
grep "requests per second" 16C_16S_1GB_redis_mixed_results.txt 2>/dev/null || echo "Mixed results not found"

echo ""
echo "🎯 COMPARATIVE ANALYSIS:"
echo "========================"

# Extract RPS from both configurations
SET_32S=$(cat 16C_32S_1GB_redis_set_results.csv 2>/dev/null | grep "SET" | cut -d',' -f2 | tr -d '"' || echo "N/A")
SET_16S=$(cat 16C_16S_1GB_redis_set_results.csv 2>/dev/null | grep "SET" | cut -d',' -f2 | tr -d '"' || echo "N/A")

GET_32S=$(cat 16C_32S_1GB_redis_get_results.csv 2>/dev/null | grep "GET" | cut -d',' -f2 | tr -d '"' || echo "N/A")
GET_16S=$(cat 16C_16S_1GB_redis_get_results.csv 2>/dev/null | grep "GET" | cut -d',' -f2 | tr -d '"' || echo "N/A")

echo "32 Shards SET RPS: $SET_32S"
echo "16 Shards SET RPS: $SET_16S"
echo "32 Shards GET RPS: $GET_32S" 
echo "16 Shards GET RPS: $GET_16S"

echo ""
echo "📁 All detailed results saved to:"
echo "- 16C_32S_1GB_*.txt/csv (32 shards configuration)"
echo "- 16C_16S_1GB_*.txt/csv (16 shards configuration)"
echo ""
echo "🚀 PHASE 6 STEP 1 SSD-TIERING-POC BENCHMARKS COMPLETE! 🚀"