#!/bin/bash

echo "🚀 PERFORMANCE COMPARISON: Original vs Optimized Multi-Core Architecture"
echo "========================================================================"
echo "Testing Phase 5 Step 1 Original (O(n) lookup) vs Optimized (O(1) lookup)"
echo ""

# Configuration
ORIGINAL_PORT=6391
OPTIMIZED_PORT=6392
TEST_KEYS=1000
CONCURRENT_CLIENTS=20

echo "📊 Test Configuration:"
echo "   Test keys: ${TEST_KEYS}"
echo "   Concurrent clients: ${CONCURRENT_CLIENTS}"
echo "   Original (O(n) lookup) port: ${ORIGINAL_PORT}"
echo "   Optimized (O(1) lookup) port: ${OPTIMIZED_PORT}"
echo ""

# Function to build and start server
build_and_start_server() {
    local source_file=$1
    local binary_name=$2
    local port=$3
    local server_name=$4
    
    echo "🔧 Building $server_name..."
    g++ -std=c++20 -pthread -O2 $source_file -o build/$binary_name
    
    if [ $? -ne 0 ]; then
        echo "❌ Build failed for $server_name"
        return 1
    fi
    
    echo "✅ Build successful for $server_name"
    
    # Start server
    echo "🚀 Starting $server_name on port $port..."
    nohup ./build/$binary_name -h 127.0.0.1 -p $port -s 4 -m 128 > /tmp/${binary_name}_test.log 2>&1 &
    local server_pid=$!
    echo "Server PID: $server_pid"
    
    # Wait for server to start
    sleep 3
    
    # Check if server is running
    if ps -p $server_pid > /dev/null; then
        echo "✅ $server_name is running"
        return 0
    else
        echo "❌ $server_name failed to start"
        echo "Log:"
        tail -10 /tmp/${binary_name}_test.log
        return 1
    fi
}

# Function to run performance test
run_performance_test() {
    local port=$1
    local server_name=$2
    local result_file=$3
    
    echo ""
    echo "🔥 Running performance test for $server_name"
    echo "============================================="
    
    # Test connectivity first
    if redis-cli -h 127.0.0.1 -p $port ping > /dev/null 2>&1; then
        echo "✅ Server connectivity confirmed"
    else
        echo "❌ Cannot connect to server on port $port"
        return 1
    fi
    
    # Run SET benchmark
    echo "📈 Testing SET operations..."
    redis-benchmark -h 127.0.0.1 -p $port -t set -n $TEST_KEYS -c $CONCURRENT_CLIENTS -d 100 -q > $result_file
    
    if [ $? -eq 0 ]; then
        echo "✅ SET benchmark completed"
        local set_rps=$(cat $result_file | grep "SET:" | awk '{print $2}')
        echo "   SET RPS: $set_rps"
    else
        echo "❌ SET benchmark failed"
        return 1
    fi
    
    # Run GET benchmark  
    echo "📈 Testing GET operations..."
    redis-benchmark -h 127.0.0.1 -p $port -t get -n $TEST_KEYS -c $CONCURRENT_CLIENTS -d 100 -q >> $result_file
    
    if [ $? -eq 0 ]; then
        echo "✅ GET benchmark completed"
        local get_rps=$(cat $result_file | grep "GET:" | awk '{print $2}')
        echo "   GET RPS: $get_rps"
    else
        echo "❌ GET benchmark failed"
        return 1
    fi
    
    # Manual test with specific keys
    echo "🔍 Manual verification test..."
    redis-cli -h 127.0.0.1 -p $port SET test_key_${server_name} "performance_test_value" > /dev/null
    local get_result=$(redis-cli -h 127.0.0.1 -p $port GET test_key_${server_name})
    
    if [ "$get_result" = "performance_test_value" ]; then
        echo "✅ Manual verification passed"
    else
        echo "❌ Manual verification failed: got '$get_result'"
    fi
    
    return 0
}

# Function to monitor CPU usage
monitor_cpu_usage() {
    local duration=$1
    local output_file=$2
    local description=$3
    
    echo "📊 Monitoring CPU usage for $description ($duration seconds)..."
    top -b -n $duration -d 1 | grep -E "(Cpu|meteor)" > $output_file &
    local monitor_pid=$!
    return $monitor_pid
}

# Clean up any existing processes
echo "🧹 Cleaning up existing processes..."
pkill -f "meteor.*-p (6391|6392)" 2>/dev/null || true
sleep 2

cd meteor

# Test 1: Original Multi-Core Implementation (O(n) lookup)
echo ""
echo "🔬 TEST 1: Original Multi-Core Implementation (O(n) Shard Lookup)"
echo "================================================================="

if build_and_start_server "sharded_server_phase5_step1_multicore_eventloop.cpp" "meteor_original" $ORIGINAL_PORT "Original Multi-Core"; then
    run_performance_test $ORIGINAL_PORT "Original Multi-Core" "/tmp/original_results.txt"
    ORIGINAL_SUCCESS=true
else
    ORIGINAL_SUCCESS=false
fi

# Kill original server
pkill -f "meteor_original" 2>/dev/null || true
sleep 2

# Test 2: Optimized Multi-Core Implementation (O(1) lookup)
echo ""
echo "🔬 TEST 2: Optimized Multi-Core Implementation (O(1) Shard Lookup)"
echo "=================================================================="

if build_and_start_server "sharded_server_phase5_step1_multicore_eventloop_optimized.cpp" "meteor_optimized" $OPTIMIZED_PORT "Optimized Multi-Core"; then
    run_performance_test $OPTIMIZED_PORT "Optimized Multi-Core" "/tmp/optimized_results.txt"
    OPTIMIZED_SUCCESS=true
else
    OPTIMIZED_SUCCESS=false
fi

# Kill optimized server
pkill -f "meteor_optimized" 2>/dev/null || true

# Performance Comparison
echo ""
echo "📊 PERFORMANCE COMPARISON RESULTS"
echo "================================="

if [ "$ORIGINAL_SUCCESS" = true ] && [ "$OPTIMIZED_SUCCESS" = true ]; then
    echo ""
    echo "🔍 Original Multi-Core (O(n) Shard Lookup) Results:"
    if [ -f "/tmp/original_results.txt" ]; then
        cat /tmp/original_results.txt
    else
        echo "   No results available"
    fi
    
    echo ""
    echo "🔍 Optimized Multi-Core (O(1) Shard Lookup) Results:"
    if [ -f "/tmp/optimized_results.txt" ]; then
        cat /tmp/optimized_results.txt
    else
        echo "   No results available"
    fi
    
    echo ""
    echo "🎯 PERFORMANCE ANALYSIS:"
    echo "======================="
    echo "✅ Key Optimizations in Optimized Version:"
    echo "   • O(1) shard-to-core mapping (eliminates linear search)"
    echo "   • Direct shard access without cross-core communication"  
    echo "   • Dragonfly-style shared-nothing architecture"
    echo "   • Zero fallback mechanisms that cause performance degradation"
    echo ""
    echo "📈 Expected Improvements:"
    echo "   • Dramatically higher RPS due to O(1) vs O(n) lookup"
    echo "   • Lower CPU usage per request"
    echo "   • Better scalability with more shards"
    echo "   • Consistent performance regardless of shard count"
    
elif [ "$ORIGINAL_SUCCESS" = true ]; then
    echo "✅ Original version tested successfully"
    echo "❌ Optimized version failed - check build or runtime issues"
    
elif [ "$OPTIMIZED_SUCCESS" = true ]; then
    echo "❌ Original version failed - check build or runtime issues"  
    echo "✅ Optimized version tested successfully"
    
else
    echo "❌ Both tests failed - check system resources and build environment"
fi

echo ""
echo "📋 Log Files Created:"
echo "   /tmp/original_results.txt - Original version benchmark results"
echo "   /tmp/optimized_results.txt - Optimized version benchmark results"
echo "   /tmp/meteor_original_test.log - Original server log"
echo "   /tmp/meteor_optimized_test.log - Optimized server log"

echo ""
echo "🎯 CONCLUSION:"
echo "============="
echo "The optimized version eliminates the O(n) linear search bottleneck"
echo "that was causing performance degradation in the original multi-core"
echo "implementation. This should result in significantly higher throughput"
echo "and better CPU utilization across all cores." 