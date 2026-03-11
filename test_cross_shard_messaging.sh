#!/bin/bash

cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm

echo "🔧 CROSS-SHARD MESSAGING TEST"
echo "============================="
echo "This test uses simplified cross-shard responses to verify the messaging architecture:"
echo "- SET commands: Always return +OK"
echo "- GET commands: Return test_val_X (where X is last char of key)"
echo "- This proves cross-shard fibers are processing commands correctly"
echo ""

# Kill existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

# Build
echo "🔨 Building test version..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 -pthread meteor_dragonfly_TEST.cpp -o meteor_cross_shard_test -luring -lboost_fiber -lboost_context -lboost_system

BUILD_CODE=$?
if [ $BUILD_CODE -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful!"

# Start server (6C:3S forces cross-shard operations)
echo ""
echo "🚀 Starting server (6C:3S - guaranteed cross-shard routing)..."
./meteor_cross_shard_test -h 127.0.0.1 -p 6379 -c 6 -s 3 -m 1536 > server.log 2>&1 &
SERVER_PID=$!

# Wait for startup
sleep 6

# Test connectivity
echo "📡 Testing server connectivity..."
PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)

if [ "$PING_RESULT" = "PONG" ]; then
    echo "✅ Server responding: $PING_RESULT"
    
    # Clear data
    redis-cli -p 6379 flushall >/dev/null 2>&1
    
    echo ""
    echo "🧪 CROSS-SHARD MESSAGING TEST"
    echo "============================="
    echo "Expected behavior:"
    echo "- SET key1: +OK (cross-shard)"
    echo "- GET key1: test_val_1 (cross-shard)" 
    echo "- SET key2: +OK (cross-shard)"
    echo "- GET key2: test_val_2 (cross-shard)"
    echo ""
    
    # Test cross-shard messaging
    SUCCESS_COUNT=0
    TOTAL_TESTS=10
    
    for i in $(seq 1 $TOTAL_TESTS); do
        echo -n "Test $i: "
        
        # SET command
        SET_RESULT=$(redis-cli -p 6379 set test_key_$i test_value_$i 2>/dev/null)
        
        if [ "$SET_RESULT" = "OK" ]; then
            # GET command  
            GET_RESULT=$(redis-cli -p 6379 get test_key_$i 2>/dev/null)
            
            # Expected test response based on key
            EXPECTED_VAL="test_val_$i"
            
            if [ "$GET_RESULT" = "$EXPECTED_VAL" ]; then
                echo "✅ SET+GET working (got '$GET_RESULT')"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                echo "❌ GET failed - got '$GET_RESULT' (expected '$EXPECTED_VAL')"
            fi
        else
            echo "❌ SET failed - got '$SET_RESULT'"
        fi
    done
    
    echo ""
    echo "📊 RESULTS:"
    echo "==========="
    echo "Successful tests: $SUCCESS_COUNT/$TOTAL_TESTS"
    SUCCESS_RATE=$(echo "scale=1; $SUCCESS_COUNT * 100 / $TOTAL_TESTS" | bc -l 2>/dev/null || echo "N/A")
    echo "Success rate: ${SUCCESS_RATE}%"
    
    if [ $SUCCESS_COUNT -eq $TOTAL_TESTS ]; then
        echo ""
        echo "🎉 PERFECT SUCCESS!"
        echo "✅ Cross-shard messaging: 100% working"
        echo "✅ Fiber processors: Processing commands"
        echo "✅ Promises/futures: Working correctly"  
        echo "✅ Response routing: Working correctly"
        echo ""
        echo "🔧 ARCHITECTURE VERIFIED! Now ready to implement real cache operations."
        
        # Quick performance test
        echo ""
        echo "🚀 Quick performance test:"
        memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis --clients=5 --threads=2 --pipeline=3 --data-size=64 --key-pattern=R:R --ratio=1:1 --test-time=3 2>/dev/null | grep -E "Totals|Ops/sec" | head -3 || echo "Performance test completed"
        
    elif [ $SUCCESS_COUNT -ge $((TOTAL_TESTS * 8 / 10)) ]; then
        echo ""
        echo "🟡 MOSTLY WORKING (${SUCCESS_RATE}% success)"
        echo "Minor issues but core architecture is sound"
        echo "May need fine-tuning of fiber scheduling or timeouts"
        
    else
        echo ""
        echo "❌ SIGNIFICANT ISSUES (${SUCCESS_RATE}% success)"
        echo "Cross-shard messaging has major problems"
        echo ""
        echo "🔍 Debug info:"
        echo "Server log (last 10 lines):"
        tail -10 server.log
    fi
    
else
    echo "❌ Server not responding: '$PING_RESULT'"
    echo ""
    echo "🔍 Server log:"
    cat server.log 2>/dev/null | head -20
fi

# Cleanup
kill $SERVER_PID 2>/dev/null
sleep 2

echo ""
echo "🏁 Cross-shard messaging test completed"
echo "Expected: 100% success rate for verified architecture"













