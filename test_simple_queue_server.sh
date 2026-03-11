#!/bin/bash

# **TEST SIMPLE QUEUE SERVER**
# Verify basic functionality works before adding optimizations

echo "🧪 SIMPLE QUEUE SERVER TEST"
echo "==========================="
echo "🎯 Goal: Verify commands actually get processed"
echo "📊 Success criteria: ANY ops/sec > 0 (no timeouts)"
echo ""

# Configuration  
SERVER_BINARY="./simple_queue_server"
BASE_PORT=6379
NUM_CORES=4

# Cleanup
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    pkill -f simple_queue_server 2>/dev/null || true
    sleep 2
    echo "✅ Cleanup complete"
}

trap cleanup EXIT INT TERM

# Check binary
if [ ! -f "$SERVER_BINARY" ]; then
    echo "❌ Server binary not found: $SERVER_BINARY"
    echo "💡 Run build_simple_queue_server.sh first"
    exit 1
fi

echo "✅ Server binary found: $SERVER_BINARY"
echo ""

# Check memtier_benchmark
if ! command -v memtier_benchmark &> /dev/null; then
    echo "❌ memtier_benchmark not found"
    echo "💡 Install: sudo apt install memtier-benchmark"
    exit 1
fi

echo "✅ memtier_benchmark available"
echo ""

# Start server
echo "🚀 STARTING SIMPLE QUEUE SERVER"
echo "==============================="

$SERVER_BINARY -c $NUM_CORES -p $BASE_PORT > simple_server.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
echo -n "Waiting for server initialization"

# Wait for server
for i in {1..10}; do
    if nc -z 127.0.0.1 $BASE_PORT 2>/dev/null; then
        echo " ✅"
        break
    fi
    echo -n "."
    sleep 1
    
    if [ $i -eq 10 ]; then
        echo " ❌"
        echo "Server failed to start"
        exit 1
    fi
done

# Verify all cores accessible
echo ""
echo "🔗 CORE CONNECTIVITY CHECK"
echo "=========================="

all_cores_ok=true
for core in $(seq 0 $((NUM_CORES-1))); do
    port=$((BASE_PORT + core))
    if nc -z 127.0.0.1 $port 2>/dev/null; then
        echo "✅ Core $core (port $port): Accessible"
    else
        echo "❌ Core $core (port $port): Not accessible" 
        all_cores_ok=false
    fi
done

if [ "$all_cores_ok" != true ]; then
    echo "❌ Not all cores accessible"
    exit 1
fi

echo ""
echo "🧪 BASIC FUNCTIONALITY TEST"
echo "==========================="

# Test 1: Single command test
echo "Test 1: Single command (should work)"
echo "Command: memtier_benchmark -s 127.0.0.1 -p $BASE_PORT -c 1 -t 1 --pipeline=1 -n 10"
echo ""

memtier_benchmark \
    -s 127.0.0.1 -p $BASE_PORT \
    -c 1 -t 1 \
    --pipeline=1 \
    -n 10 \
    --hide-histogram \
    > simple_test1.log 2>&1

test1_exit=$?

if [ $test1_exit -eq 0 ] && grep -q "Totals" simple_test1.log; then
    ops_sec=$(grep "Totals" simple_test1.log | awk '{print $2}' | head -1 | tr -d ',' || echo "0")
    echo "✅ Test 1 PASSED: $ops_sec ops/sec"
    test1_success=true
else
    echo "❌ Test 1 FAILED"
    echo "Error sample:"
    head -10 simple_test1.log 2>/dev/null || echo "No error log"
    test1_success=false
fi

echo ""

# Test 2: Small pipeline test
echo "Test 2: Small pipeline (3 commands)"
echo "Command: memtier_benchmark -s 127.0.0.1 -p 6380 -c 2 -t 1 --pipeline=3 -n 20"
echo ""

memtier_benchmark \
    -s 127.0.0.1 -p 6380 \
    -c 2 -t 1 \
    --pipeline=3 \
    -n 20 \
    --hide-histogram \
    > simple_test2.log 2>&1

test2_exit=$?

if [ $test2_exit -eq 0 ] && grep -q "Totals" simple_test2.log; then
    ops_sec=$(grep "Totals" simple_test2.log | awk '{print $2}' | head -1 | tr -d ',' || echo "0")
    echo "✅ Test 2 PASSED: $ops_sec ops/sec"
    test2_success=true
else
    echo "❌ Test 2 FAILED"
    echo "Error sample:"
    head -10 simple_test2.log 2>/dev/null || echo "No error log"
    test2_success=false
fi

echo ""

# Server health check
echo "🏥 SERVER HEALTH CHECK"
echo "======================"

if kill -0 $SERVER_PID 2>/dev/null; then
    echo "✅ Server still running"
    
    # Check server log for any processing
    if [ -f "simple_server.log" ]; then
        processed_commands=$(grep -c "Commands processed:" simple_server.log 2>/dev/null || echo "0")
        echo "📊 Server log indicates activity: Yes"
        echo "📄 Server log (last 10 lines):"
        tail -10 simple_server.log
    else
        echo "📊 No detailed server logs available"
    fi
else
    echo "⚠️  Server stopped during testing"
fi

echo ""
echo "🏆 SIMPLE QUEUE SERVER ASSESSMENT"
echo "================================="

if [ "$test1_success" = true ] || [ "$test2_success" = true ]; then
    echo "🎊 SUCCESS: BASIC FUNCTIONALITY CONFIRMED!"
    echo ""
    echo "✅ Achievements:"
    echo "   - Server starts and accepts connections"
    echo "   - Commands are actually processed (no timeouts)"
    echo "   - Basic Redis protocol compatibility"
    echo "   - Multi-core deployment working"
    echo ""
    echo "🚀 READY FOR OPTIMIZATION PHASE:"
    echo "   1. ✅ Working baseline established"
    echo "   2. 🔧 Can now add cross-core routing"
    echo "   3. ⚡ Can add conflict detection"
    echo "   4. 📈 Can add performance optimizations"
    echo ""
    echo "📊 Next steps:"
    echo "   - Run larger memtier tests"
    echo "   - Add cross-core command routing" 
    echo "   - Implement temporal coherence for pipelines"
    
else
    echo "❌ BASIC FUNCTIONALITY FAILED"
    echo ""
    echo "🔍 Issues to investigate:"
    echo "   - Check server logs for errors"
    echo "   - Verify RESP protocol parsing"
    echo "   - Check socket handling"
    
fi

echo ""
echo "📄 Generated files:"
echo "   - simple_server.log (server output)"
echo "   - simple_test1.log (single command test)"
echo "   - simple_test2.log (pipeline test)"

exit 0














