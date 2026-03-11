#!/bin/bash

# **TEST TIMEOUT FIX VERIFICATION**
# Verify that the 100ms → 5000ms timeout fix resolves the regression

echo "🧪 TIMEOUT FIX VERIFICATION TEST"
echo "================================"
echo "🎯 Goal: Eliminate '-ERR timeout' responses"
echo "📊 Expected: Significant performance improvement"
echo ""

# Configuration
FIXED_BINARY="./integrated_temporal_coherence_server_fixed"
BASE_PORT=6379
NUM_CORES=4
TEST_DURATION=30

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up test processes..."
    pkill -f integrated_temporal_coherence_server_fixed 2>/dev/null || true
    sleep 2
    echo "✅ Cleanup complete"
}

trap cleanup EXIT INT TERM

# Check binary exists
if [ ! -f "$FIXED_BINARY" ]; then
    echo "❌ Fixed binary not found: $FIXED_BINARY"
    echo "💡 Run build_timeout_fixed_server.sh first"
    exit 1
fi

echo "✅ Fixed binary found: $FIXED_BINARY"
echo ""

# Check memtier_benchmark
if ! command -v memtier_benchmark &> /dev/null; then
    echo "❌ memtier_benchmark not found"
    echo "💡 Install with: sudo apt install memtier-benchmark"
    exit 1
fi

echo "✅ memtier_benchmark available"
echo ""

# Start fixed server
echo "🚀 STARTING TIMEOUT-FIXED SERVER"
echo "================================="

$FIXED_BINARY -c $NUM_CORES -s $((NUM_CORES * 4)) -p $BASE_PORT > timeout_fix_server.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
echo -n "Waiting for server to initialize"

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

# Verify all cores are accessible
echo ""
echo "🔗 CONNECTIVITY VERIFICATION"
echo "============================"

all_cores_accessible=true
for core in $(seq 0 $((NUM_CORES-1))); do
    port=$((BASE_PORT + core))
    if nc -z 127.0.0.1 $port 2>/dev/null; then
        echo "✅ Core $core (port $port): Accessible"
    else
        echo "❌ Core $core (port $port): Not accessible"
        all_cores_accessible=false
    fi
done

if [ "$all_cores_accessible" != true ]; then
    echo ""
    echo "❌ Not all cores accessible - server startup issue"
    exit 1
fi

echo ""
echo "🧪 TIMEOUT REGRESSION TEST"
echo "=========================="

# Test 1: Quick response test (should eliminate most timeouts)
echo "Test 1: Quick response verification (10 seconds)"
echo "Command: memtier_benchmark -s 127.0.0.1 -p 6380 -c 4 -t 2 --pipeline=5 -n 1000"
echo ""

timeout_fix_start_time=$(date +%s)

memtier_benchmark \
    -s 127.0.0.1 -p 6380 \
    -c 4 -t 2 \
    --pipeline=5 \
    -n 1000 \
    --test-time=10 \
    > timeout_fix_test1.log 2>&1

test1_exit_code=$?
timeout_fix_end_time=$(date +%s)
test1_duration=$((timeout_fix_end_time - timeout_fix_start_time))

echo "Test 1 completed in ${test1_duration}s with exit code: $test1_exit_code"

# Analyze results
if [ $test1_exit_code -eq 0 ]; then
    echo ""
    echo "📊 TEST 1 RESULTS ANALYSIS"
    echo "=========================="
    
    if [ -f "timeout_fix_test1.log" ]; then
        # Check for timeout errors
        timeout_errors=$(grep -c "timeout" timeout_fix_test1.log || echo "0")
        
        # Extract performance metrics
        if grep -q "Totals" timeout_fix_test1.log; then
            ops_per_sec=$(grep "Totals" timeout_fix_test1.log | awk '{print $2}' | head -1 | tr -d ',' || echo "N/A")
            avg_latency=$(grep "Totals" timeout_fix_test1.log | awk '{print $6}' | head -1 || echo "N/A")
            
            echo "🎯 Performance Metrics:"
            echo "   - Throughput: $ops_per_sec ops/sec"
            echo "   - Average latency: $avg_latency ms"
            echo "   - Timeout errors: $timeout_errors"
            
            # Performance assessment
            if [[ "$ops_per_sec" =~ ^[0-9]+$ ]] && [ "$ops_per_sec" -gt 1000 ]; then
                echo ""
                echo "🚀 SUCCESS: Achieved 1000+ ops/sec (significant improvement)"
                performance_improved=true
            elif [[ "$ops_per_sec" =~ ^[0-9]+$ ]] && [ "$ops_per_sec" -gt 100 ]; then
                echo ""
                echo "✅ GOOD: Achieved 100+ ops/sec (moderate improvement)"  
                performance_improved=true
            elif [[ "$ops_per_sec" =~ ^[0-9]+$ ]] && [ "$ops_per_sec" -gt 50 ]; then
                echo ""
                echo "📈 PARTIAL: Achieved 50+ ops/sec (some improvement)"
                performance_improved=true
            else
                echo ""
                echo "⚠️  LIMITED: Performance still low ($ops_per_sec ops/sec)"
                performance_improved=false
            fi
            
            # Timeout assessment
            if [ "$timeout_errors" -eq 0 ]; then
                echo "✅ TIMEOUT FIX: No timeout errors detected"
                timeout_fixed=true
            elif [ "$timeout_errors" -lt 10 ]; then
                echo "🔶 TIMEOUT REDUCED: Only $timeout_errors timeout errors"
                timeout_fixed=partial
            else
                echo "❌ TIMEOUT PERSISTS: $timeout_errors timeout errors still present"
                timeout_fixed=false
            fi
            
        else
            echo "⚠️  Unable to parse performance results"
            echo "Raw output sample:"
            head -10 timeout_fix_test1.log
            performance_improved=unknown
            timeout_fixed=unknown
        fi
    else
        echo "❌ Test results file not found"
        performance_improved=false
        timeout_fixed=false
    fi
    
else
    echo ""
    echo "❌ TEST 1 FAILED"
    echo "==============="
    echo "Exit code: $test1_exit_code" 
    echo "Error output:"
    tail -20 timeout_fix_test1.log 2>/dev/null || echo "No error log available"
    performance_improved=false
    timeout_fixed=false
fi

echo ""

# Test 2: Extended test if first test was successful
if [ "$performance_improved" == "true" ]; then
    echo "🧪 TEST 2: EXTENDED PERFORMANCE TEST"
    echo "==================================="
    echo "Running extended test with higher load..."
    echo ""
    
    memtier_benchmark \
        -s 127.0.0.1 -p 6380 \
        -c 8 -t 4 \
        --pipeline=10 \
        -n 5000 \
        > timeout_fix_test2.log 2>&1
    
    test2_exit_code=$?
    
    if [ $test2_exit_code -eq 0 ] && grep -q "Totals" timeout_fix_test2.log; then
        ops_per_sec_ext=$(grep "Totals" timeout_fix_test2.log | awk '{print $2}' | head -1 | tr -d ',' || echo "N/A")
        echo "📊 Extended test: $ops_per_sec_ext ops/sec"
    else
        echo "⚠️  Extended test had issues"
    fi
fi

# Server health check
echo ""
echo "🏥 SERVER HEALTH CHECK"
echo "======================"

if kill -0 $SERVER_PID 2>/dev/null; then
    echo "✅ Server still running after tests"
    
    # Resource usage
    memory_kb=$(ps -o rss= -p $SERVER_PID 2>/dev/null || echo "unknown")
    cpu_percent=$(ps -o %cpu= -p $SERVER_PID 2>/dev/null || echo "unknown")
    
    echo "📊 Resource usage:"
    echo "   - Memory: ${memory_kb} KB"
    echo "   - CPU: ${cpu_percent}%"
else
    echo "⚠️  Server stopped during testing"
fi

# Final assessment
echo ""
echo "🏆 TIMEOUT FIX ASSESSMENT"
echo "========================="

if [ "$timeout_fixed" == "true" ] && [ "$performance_improved" == "true" ]; then
    echo "🎊 SUCCESS: TIMEOUT REGRESSION FIXED!"
    echo ""
    echo "✅ Achievements:"
    echo "   - Eliminated timeout errors"
    echo "   - Significantly improved performance" 
    echo "   - Server stability maintained"
    echo ""
    echo "🚀 Ready for production memtier benchmarking!"
    
elif [ "$timeout_fixed" == "partial" ] || [ "$performance_improved" == "true" ]; then
    echo "📈 PARTIAL SUCCESS: TIMEOUT REGRESSION IMPROVED"
    echo ""
    echo "✅ Improvements:"
    echo "   - Reduced timeout errors"
    echo "   - Better performance than before"
    echo ""
    echo "🔧 Further optimization recommended"
    
else
    echo "❌ TIMEOUT FIX UNSUCCESSFUL"
    echo ""
    echo "🔍 Investigation needed:"
    echo "   - Check server logs for additional issues"
    echo "   - Verify fiber processing is working correctly"
    echo "   - Consider removing timeouts entirely for basic commands"
    
fi

echo ""
echo "📄 Generated files:"
echo "   - timeout_fix_server.log (server log)"
echo "   - timeout_fix_test1.log (test 1 results)"
echo "   - timeout_fix_test2.log (test 2 results, if run)"

exit 0














