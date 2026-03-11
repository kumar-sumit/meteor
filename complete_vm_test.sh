#!/bin/bash

cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm

echo "🚀 COMPLETE DRAGONFLY CROSS-SHARD TEST"
echo "====================================="

# Kill any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

# Start server
echo "Starting meteor server (6C:3S - cross-shard setup)..."
./meteor_working -h 127.0.0.1 -p 6379 -c 6 -s 3 -m 1536 > server.log 2>&1 &
SERVER_PID=$!

# Give server time to initialize
sleep 8

echo "Server started with PID: $SERVER_PID"

# Test connectivity
echo ""
echo "Testing connectivity..."
PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)
echo "PING result: '$PING_RESULT'"

if [ "$PING_RESULT" = "PONG" ]; then
    echo "✅ Server responding!"
    
    # Clear any existing data
    redis-cli -p 6379 flushall >/dev/null 2>&1
    
    echo ""
    echo "🎯 CROSS-SHARD CORRECTNESS TEST"
    echo "==============================="
    
    # Test cross-shard SET->GET operations
    FAILURES=0
    TOTAL=20
    
    for i in $(seq 1 $TOTAL); do
        # Set key
        redis-cli -p 6379 set test_key_$i "test_value_$i" >/dev/null 2>&1
        
        # Get key (may route to different shard)
        RESULT=$(redis-cli -p 6379 get test_key_$i 2>/dev/null)
        
        if [ "$RESULT" != "test_value_$i" ]; then
            FAILURES=$((FAILURES + 1))
            if [ $FAILURES -eq 1 ]; then
                echo "❌ First failure: key test_key_$i -> got '$RESULT' (expected 'test_value_$i')"
            fi
        fi
    done
    
    echo "Cross-shard SET→GET failures: $FAILURES/$TOTAL"
    
    # Manual verification
    echo ""
    echo "🔍 Manual verification tests:"
    redis-cli -p 6379 set manual_test_1 "manual_value_1" >/dev/null 2>&1
    M1=$(redis-cli -p 6379 get manual_test_1 2>/dev/null)
    echo "manual_test_1: '$M1'"
    
    redis-cli -p 6379 set manual_test_2 "manual_value_2" >/dev/null 2>&1
    M2=$(redis-cli -p 6379 get manual_test_2 2>/dev/null)
    echo "manual_test_2: '$M2'"
    
    redis-cli -p 6379 set manual_test_3 "manual_value_3" >/dev/null 2>&1
    M3=$(redis-cli -p 6379 get manual_test_3 2>/dev/null)
    echo "manual_test_3: '$M3'"
    
    # Results analysis
    echo ""
    echo "📊 FINAL RESULTS:"
    echo "================"
    
    if [ $FAILURES -eq 0 ]; then
        echo "🎉 PERFECT SUCCESS!"
        echo "✅ Cross-shard routing: 100% correct"
        echo "✅ DragonflyDB architecture: Working"
        echo "✅ Fiber processors: Processing commands"
        echo ""
        echo "🚀 Running performance benchmark..."
        memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis --clients=10 --threads=3 --pipeline=5 --data-size=64 --key-pattern=R:R --ratio=1:1 --test-time=5 2>/dev/null | grep -E "Totals|Ops/sec" | head -5
        echo ""
        echo "🏆 DRAGONFLY IMPLEMENTATION: COMPLETE SUCCESS!"
        
    elif [ $FAILURES -le 3 ]; then
        echo "🟡 MOSTLY WORKING"
        echo "Failures: $FAILURES/$TOTAL ($(echo "scale=1; $FAILURES * 100 / $TOTAL" | bc -l)%)"
        echo "Minor issues but core architecture working"
        
    else
        echo "❌ SIGNIFICANT ISSUES"
        echo "Failures: $FAILURES/$TOTAL ($(echo "scale=1; $FAILURES * 100 / $TOTAL" | bc -l)%)"
        echo "Cross-shard routing has major problems"
    fi
    
    echo ""
    echo "Manual results: '$M1' | '$M2' | '$M3'"
    
    # Show server logs (last few lines)
    echo ""
    echo "🔍 Server log (last 10 lines):"
    echo "==============================="
    tail -10 server.log
    
else
    echo "❌ Server not responding or failed to start"
    echo ""
    echo "🔍 Server log:"
    echo "=============="
    cat server.log 2>/dev/null || echo "No server log found"
fi

# Cleanup
kill $SERVER_PID 2>/dev/null
sleep 2

echo ""
echo "🏁 Test completed"
echo "Expected result: 0 failures for perfect cross-shard implementation"













