#!/bin/bash

echo "🚀 Multi-Core Server Performance Load Test"
echo "=========================================="
echo "Testing Phase 5 Step 1 vs Phase 4 Step 3 Performance"
echo ""

# Configuration
PHASE4_PORT=6390
PHASE5_PORT=6391
TEST_DURATION=30  # seconds
CONCURRENT_CLIENTS=50

echo "📊 Test Configuration:"
echo "   Duration: ${TEST_DURATION} seconds"
echo "   Concurrent clients: ${CONCURRENT_CLIENTS}"
echo "   Phase 4 Step 3 port: ${PHASE4_PORT}"
echo "   Phase 5 Step 1 port: ${PHASE5_PORT}"
echo ""

# Function to run redis-benchmark
run_benchmark() {
    local port=$1
    local test_name=$2
    local log_file=$3
    
    echo "🔥 Running benchmark: $test_name"
    redis-benchmark -h 127.0.0.1 -p $port -t set,get -n 100000 -c $CONCURRENT_CLIENTS -d 100 --csv > $log_file 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ $test_name completed"
        echo "Results:"
        cat $log_file | grep -E "(SET|GET)" | head -2
    else
        echo "❌ $test_name failed"
        tail -5 $log_file
    fi
    echo ""
}

# Function to monitor CPU usage
monitor_cpu() {
    local duration=$1
    local output_file=$2
    local server_name=$3
    
    echo "📈 Monitoring CPU usage for $server_name ($duration seconds)"
    top -b -n $duration -d 1 | grep -E "(Cpu|meteor)" > $output_file &
    CPU_PID=$!
    
    return $CPU_PID
}

# Start Phase 4 Step 3 server (single-threaded event loop)
echo "🔧 Starting Phase 4 Step 3 Server (Single Event Loop)"
cd meteor
nohup ./build/meteor_phase4_step3_complete -p $PHASE4_PORT -s 22 -m 256 > /tmp/phase4_load_test.log 2>&1 &
PHASE4_PID=$!
echo "Phase 4 PID: $PHASE4_PID"
sleep 5

# Test Phase 4 Step 3 performance
if ps -p $PHASE4_PID > /dev/null; then
    echo "✅ Phase 4 server running"
    run_benchmark $PHASE4_PORT "Phase 4 Step 3 (Single Event Loop)" "/tmp/phase4_benchmark.csv"
    
    # Monitor CPU for Phase 4
    monitor_cpu 10 "/tmp/phase4_cpu.log" "Phase 4"
    PHASE4_CPU_PID=$!
    
    # Quick test
    redis-benchmark -h 127.0.0.1 -p $PHASE4_PORT -t set -n 10000 -c 10 -q | head -1
    
    kill $PHASE4_CPU_PID 2>/dev/null
else
    echo "❌ Phase 4 server failed to start"
fi

# Kill Phase 4 server
kill $PHASE4_PID 2>/dev/null
sleep 2

echo ""
echo "🔧 Starting Phase 5 Step 1 Server (Multi-Core Event Loops)"
nohup ./build/meteor_multicore_resp_fixed -h 127.0.0.1 -p $PHASE5_PORT -s 22 -m 256 > /tmp/phase5_load_test.log 2>&1 &
PHASE5_PID=$!
echo "Phase 5 PID: $PHASE5_PID"
sleep 5

# Test Phase 5 Step 1 performance
if ps -p $PHASE5_PID > /dev/null; then
    echo "✅ Phase 5 server running"
    run_benchmark $PHASE5_PORT "Phase 5 Step 1 (Multi-Core Event Loops)" "/tmp/phase5_benchmark.csv"
    
    # Monitor CPU for Phase 5
    monitor_cpu 10 "/tmp/phase5_cpu.log" "Phase 5"
    PHASE5_CPU_PID=$!
    
    # Quick test
    redis-benchmark -h 127.0.0.1 -p $PHASE5_PORT -t set -n 10000 -c 10 -q | head -1
    
    kill $PHASE5_CPU_PID 2>/dev/null
else
    echo "❌ Phase 5 server failed to start"
    echo "Log:"
    tail -10 /tmp/phase5_load_test.log
fi

# Kill Phase 5 server
kill $PHASE5_PID 2>/dev/null

echo ""
echo "📊 Performance Comparison Summary"
echo "================================="

echo ""
echo "🔍 Phase 4 Step 3 Results (Single Event Loop):"
if [ -f "/tmp/phase4_benchmark.csv" ]; then
    cat /tmp/phase4_benchmark.csv | grep -E "(SET|GET)" | head -2
else
    echo "No results available"
fi

echo ""
echo "🔍 Phase 5 Step 1 Results (Multi-Core Event Loops):"
if [ -f "/tmp/phase5_benchmark.csv" ]; then
    cat /tmp/phase5_benchmark.csv | grep -E "(SET|GET)" | head -2
else
    echo "No results available"
fi

echo ""
echo "🎯 Analysis:"
echo "============"
echo "❌ Expected Issue: Phase 5 performance degraded due to:"
echo "   • O(n) linear search in shard-to-core lookup"
echo "   • Inefficient cross-core communication"
echo "   • Multiple loops per request"
echo ""
echo "✅ Solution Needed:"
echo "   • Direct shard-to-core mapping (O(1) lookup)"
echo "   • Eliminate cross-core communication"
echo "   • Dragonfly-style shared-nothing architecture"

echo ""
echo "📋 Log files created:"
echo "   /tmp/phase4_benchmark.csv - Phase 4 benchmark results"
echo "   /tmp/phase5_benchmark.csv - Phase 5 benchmark results"
echo "   /tmp/phase4_load_test.log - Phase 4 server log"
echo "   /tmp/phase5_load_test.log - Phase 5 server log" 