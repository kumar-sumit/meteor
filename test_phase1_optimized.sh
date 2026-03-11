#!/bin/bash

# **TEST PHASE 1 OPTIMIZED SERVER**
# Validate 2M+ QPS performance with advanced optimizations

echo "🧪 PHASE 1 OPTIMIZED SERVER PERFORMANCE TEST"
echo "============================================"
echo "🎯 Target: 2M+ QPS (2.5x improvement over 800K baseline)"
echo "📊 Testing: Memory pools, zero-copy, lock-free queues, SIMD"
echo ""

# Configuration
SERVER_BINARY="./phase1_optimized_server"
BASE_PORT=7000
NUM_CORES=4
TEST_RESULTS_DIR="phase1_test_results"

# Create results directory
mkdir -p $TEST_RESULTS_DIR

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up test processes..."
    pkill -f phase1_optimized_server 2>/dev/null || true
    sleep 2
    echo "✅ Cleanup complete"
}

trap cleanup EXIT INT TERM

# Check binary
if [ ! -f "$SERVER_BINARY" ]; then
    echo "❌ Server binary not found: $SERVER_BINARY"
    echo "💡 Run build_phase1_optimized.sh first"
    exit 1
fi

echo "✅ Phase 1 optimized server found: $SERVER_BINARY"
echo ""

# Check memtier_benchmark
if ! command -v memtier_benchmark &> /dev/null; then
    echo "❌ memtier_benchmark not found"
    echo "💡 Install: sudo apt install memtier-benchmark"
    exit 1
fi

echo "✅ memtier_benchmark available"
echo ""

# Start Phase 1 optimized server
echo "🚀 STARTING PHASE 1 OPTIMIZED SERVER"
echo "===================================="

$SERVER_BINARY -c $NUM_CORES -p $BASE_PORT > $TEST_RESULTS_DIR/server.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
echo -n "Waiting for optimized server initialization"

# Wait for server startup
for i in {1..15}; do
    if nc -z 127.0.0.1 $BASE_PORT 2>/dev/null; then
        echo " ✅"
        break
    fi
    echo -n "."
    sleep 1
    
    if [ $i -eq 15 ]; then
        echo " ❌"
        echo "Server failed to start"
        exit 1
    fi
done

# Verify all cores accessible
echo ""
echo "🔗 OPTIMIZED CORE CONNECTIVITY CHECK"
echo "===================================="

all_cores_ok=true
for core in $(seq 0 $((NUM_CORES-1))); do
    port=$((BASE_PORT + core))
    if nc -z 127.0.0.1 $port 2>/dev/null; then
        echo "✅ Optimized Core $core (port $port): Accessible"
    else
        echo "❌ Optimized Core $core (port $port): Not accessible"
        all_cores_ok=false
    fi
done

if [ "$all_cores_ok" != true ]; then
    echo "❌ Not all optimized cores accessible"
    exit 1
fi

echo ""
echo "🧪 PHASE 1 PERFORMANCE TESTING SUITE"
echo "==================================="

# Test 1: Baseline performance verification
echo "Test 1: Baseline Performance Verification"
echo "Command: memtier_benchmark -s 127.0.0.1 -p $BASE_PORT -c 4 -t 4 --pipeline=5 -n 2000"
echo ""

memtier_benchmark \
    -s 127.0.0.1 -p $BASE_PORT \
    -c 4 -t 4 \
    --pipeline=5 \
    -n 2000 \
    --hide-histogram \
    --out-file=$TEST_RESULTS_DIR/test1_baseline.out \
    > $TEST_RESULTS_DIR/test1_baseline.log 2>&1

test1_exit=$?

if [ $test1_exit -eq 0 ] && [ -f "$TEST_RESULTS_DIR/test1_baseline.out" ]; then
    baseline_qps=$(grep "Totals" $TEST_RESULTS_DIR/test1_baseline.out | awk '{print $2}' | head -1 | tr -d ',' || echo "0")
    baseline_latency=$(grep "Totals" $TEST_RESULTS_DIR/test1_baseline.out | awk '{print $6}' | head -1 || echo "N/A")
    echo "✅ Test 1 Results: $baseline_qps QPS, ${baseline_latency}ms latency"
    test1_success=true
else
    echo "❌ Test 1 failed"
    test1_success=false
fi

echo ""

# Test 2: High concurrency test
echo "Test 2: High Concurrency Test (Target: 1.5M+ QPS)"
echo "Command: memtier_benchmark -s 127.0.0.1 -p $BASE_PORT -c 16 -t 8 --pipeline=10 -n 5000"
echo ""

memtier_benchmark \
    -s 127.0.0.1 -p $BASE_PORT \
    -c 16 -t 8 \
    --pipeline=10 \
    -n 5000 \
    --hide-histogram \
    --out-file=$TEST_RESULTS_DIR/test2_highconcurrency.out \
    > $TEST_RESULTS_DIR/test2_highconcurrency.log 2>&1

test2_exit=$?

if [ $test2_exit -eq 0 ] && [ -f "$TEST_RESULTS_DIR/test2_highconcurrency.out" ]; then
    highconc_qps=$(grep "Totals" $TEST_RESULTS_DIR/test2_highconcurrency.out | awk '{print $2}' | head -1 | tr -d ',' || echo "0")
    highconc_latency=$(grep "Totals" $TEST_RESULTS_DIR/test2_highconcurrency.out | awk '{print $6}' | head -1 || echo "N/A")
    echo "✅ Test 2 Results: $highconc_qps QPS, ${highconc_latency}ms latency"
    test2_success=true
else
    echo "❌ Test 2 failed"
    test2_success=false
fi

echo ""

# Test 3: Maximum performance test (Your original command optimized)
echo "Test 3: Maximum Performance Test (Target: 2M+ QPS)"
echo "Command: memtier_benchmark -s 127.0.0.1 -p $BASE_PORT -c 32 -t 16 --pipeline=20 -n 5000"
echo ""

memtier_benchmark \
    -s 127.0.0.1 -p $BASE_PORT \
    -c 32 -t 16 \
    --pipeline=20 \
    -n 5000 \
    --hide-histogram \
    --out-file=$TEST_RESULTS_DIR/test3_maximum.out \
    > $TEST_RESULTS_DIR/test3_maximum.log 2>&1

test3_exit=$?

if [ $test3_exit -eq 0 ] && [ -f "$TEST_RESULTS_DIR/test3_maximum.out" ]; then
    maximum_qps=$(grep "Totals" $TEST_RESULTS_DIR/test3_maximum.out | awk '{print $2}' | head -1 | tr -d ',' || echo "0")
    maximum_latency=$(grep "Totals" $TEST_RESULTS_DIR/test3_maximum.out | awk '{print $6}' | head -1 || echo "N/A")
    maximum_p99=$(grep "99.00" $TEST_RESULTS_DIR/test3_maximum.out | awk '{print $2}' | head -1 || echo "N/A")
    echo "✅ Test 3 Results: $maximum_qps QPS, ${maximum_latency}ms avg, ${maximum_p99}ms P99"
    test3_success=true
else
    echo "❌ Test 3 failed"
    test3_success=false
fi

echo ""

# Test 4: Deep pipeline test 
echo "Test 4: Deep Pipeline Test (Pipeline Depth 50)"
echo "Command: memtier_benchmark -s 127.0.0.1 -p $BASE_PORT -c 8 -t 4 --pipeline=50 -n 2000"
echo ""

memtier_benchmark \
    -s 127.0.0.1 -p $BASE_PORT \
    -c 8 -t 4 \
    --pipeline=50 \
    -n 2000 \
    --hide-histogram \
    --out-file=$TEST_RESULTS_DIR/test4_deeppipeline.out \
    > $TEST_RESULTS_DIR/test4_deeppipeline.log 2>&1

test4_exit=$?

if [ $test4_exit -eq 0 ] && [ -f "$TEST_RESULTS_DIR/test4_deeppipeline.out" ]; then
    pipeline_qps=$(grep "Totals" $TEST_RESULTS_DIR/test4_deeppipeline.out | awk '{print $2}' | head -1 | tr -d ',' || echo "0")
    pipeline_latency=$(grep "Totals" $TEST_RESULTS_DIR/test4_deeppipeline.out | awk '{print $6}' | head -1 || echo "N/A")
    echo "✅ Test 4 Results: $pipeline_qps QPS, ${pipeline_latency}ms latency"
    test4_success=true
else
    echo "❌ Test 4 failed"
    test4_success=false
fi

echo ""

# Server health check
echo "🏥 PHASE 1 SERVER HEALTH CHECK"
echo "=============================="

if kill -0 $SERVER_PID 2>/dev/null; then
    echo "✅ Phase 1 optimized server still running"
    
    # Check server performance metrics
    memory_usage=$(ps -o rss= -p $SERVER_PID 2>/dev/null || echo "unknown")
    cpu_usage=$(ps -o %cpu= -p $SERVER_PID 2>/dev/null || echo "unknown")
    
    echo "📊 Resource usage:"
    echo "   - Memory: ${memory_usage} KB"
    echo "   - CPU: ${cpu_usage}%"
else
    echo "⚠️  Server stopped during testing"
fi

echo ""

# Performance analysis and scoring
echo "📊 PHASE 1 PERFORMANCE ANALYSIS"
echo "==============================="

# Calculate performance improvements
baseline_simple=800000  # 800K QPS from simple queue approach

total_tests=0
passed_tests=0

echo "Performance Results Summary:"
echo "============================"

if [ "$test1_success" = true ] && [[ "$baseline_qps" =~ ^[0-9]+$ ]]; then
    improvement1=$(echo "scale=2; $baseline_qps / $baseline_simple * 100" | bc -l 2>/dev/null || echo "N/A")
    echo "Test 1 (Baseline): $baseline_qps QPS (${improvement1}% of simple baseline)"
    total_tests=$((total_tests + 1))
    if [ "$baseline_qps" -gt 800000 ]; then
        passed_tests=$((passed_tests + 1))
    fi
fi

if [ "$test2_success" = true ] && [[ "$highconc_qps" =~ ^[0-9]+$ ]]; then
    improvement2=$(echo "scale=2; $highconc_qps / $baseline_simple * 100" | bc -l 2>/dev/null || echo "N/A")
    echo "Test 2 (High Concurrency): $highconc_qps QPS (${improvement2}% of simple baseline)"
    total_tests=$((total_tests + 1))
    if [ "$highconc_qps" -gt 1500000 ]; then
        passed_tests=$((passed_tests + 1))
    fi
fi

if [ "$test3_success" = true ] && [[ "$maximum_qps" =~ ^[0-9]+$ ]]; then
    improvement3=$(echo "scale=2; $maximum_qps / $baseline_simple * 100" | bc -l 2>/dev/null || echo "N/A")
    echo "Test 3 (Maximum): $maximum_qps QPS (${improvement3}% of simple baseline)"
    total_tests=$((total_tests + 1))
    if [ "$maximum_qps" -gt 2000000 ]; then
        passed_tests=$((passed_tests + 1))
    fi
fi

if [ "$test4_success" = true ] && [[ "$pipeline_qps" =~ ^[0-9]+$ ]]; then
    improvement4=$(echo "scale=2; $pipeline_qps / $baseline_simple * 100" | bc -l 2>/dev/null || echo "N/A")
    echo "Test 4 (Deep Pipeline): $pipeline_qps QPS (${improvement4}% of simple baseline)"
    total_tests=$((total_tests + 1))
    if [ "$pipeline_qps" -gt 1000000 ]; then
        passed_tests=$((passed_tests + 1))
    fi
fi

echo ""
echo "🎯 PHASE 1 TARGET ASSESSMENT"
echo "============================"

# Determine if we hit the 2M+ QPS target
target_achieved=false
if [ "$test3_success" = true ] && [[ "$maximum_qps" =~ ^[0-9]+$ ]] && [ "$maximum_qps" -gt 2000000 ]; then
    target_achieved=true
fi

if [ "$target_achieved" = true ]; then
    echo "🎊 PHASE 1 TARGET ACHIEVED!"
    echo "=========================="
    echo "✅ Successfully reached 2M+ QPS: $maximum_qps QPS"
    echo "✅ Phase 1 optimizations working effectively"
    echo "✅ Ready to proceed to Phase 2 optimizations"
    echo ""
    echo "🚀 PHASE 1 SUCCESS BREAKDOWN:"
    echo "   - Memory Pools: Reduced allocation overhead"
    echo "   - Zero-Copy Parsing: Eliminated string copies"
    echo "   - Lock-Free Queues: Reduced synchronization overhead"  
    echo "   - SIMD Operations: Accelerated string processing"
    echo ""
    echo "📈 Next Target: Phase 2 → 4M+ QPS"
    
elif [ "$test2_success" = true ] && [[ "$highconc_qps" =~ ^[0-9]+$ ]] && [ "$highconc_qps" -gt 1500000 ]; then
    echo "📈 PHASE 1 PARTIAL SUCCESS"
    echo "========================="
    echo "✅ Achieved 1.5M+ QPS: Strong improvement over baseline"
    echo "🔧 2M+ QPS target not quite reached, but significant progress"
    echo "💡 Consider additional Phase 1 tuning or proceed to Phase 2"
    
else
    echo "⚠️  PHASE 1 TARGET NOT ACHIEVED"
    echo "=============================="
    echo "🔍 Need investigation and tuning"
    echo "📊 Current best performance: ${maximum_qps:-N/A} QPS"
    echo "🎯 Target: 2,000,000+ QPS"
    
fi

echo ""
echo "📄 Generated test files:"
echo "   - $TEST_RESULTS_DIR/server.log (server output)"
echo "   - $TEST_RESULTS_DIR/test*_*.out (memtier results)"
echo "   - $TEST_RESULTS_DIR/test*_*.log (test logs)"

echo ""
echo "🏆 PHASE 1 TESTING COMPLETE"
echo "==========================="
echo "Tests passed: $passed_tests/$total_tests"

if [ "$target_achieved" = true ]; then
    echo "Status: ✅ READY FOR PHASE 2 OPTIMIZATIONS"
    exit 0
else
    echo "Status: 🔧 NEEDS TUNING OR INVESTIGATION"
    exit 1
fi














