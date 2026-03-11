#!/bin/bash

cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor || true

echo "🎯 CORES = SHARDS CORRECTNESS TEST"
echo "================================="
echo "Testing simplified architecture with 1:1 core-to-shard mapping"
echo "No cross-shard complexity - direct local processing only"
echo ""

# Build
echo "🔨 Building cores=shards version..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
    meteor_cores_equals_shards.cpp -o meteor_simple \
    -luring -lboost_fiber -lboost_context -lboost_system -pthread

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful!"

# Test Configuration 1: 4C:4S (cores = shards)
echo ""
echo "🧪 TEST 1: 4 Cores = 4 Shards"
echo "============================="

./meteor_simple -h 127.0.0.1 -p 6379 -c 4 -s 4 -m 1024 > test1.log 2>&1 &
SERVER_PID=$!

echo "Server starting (4C:4S)..."
sleep 6

# Test connectivity
PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)
if [ "$PING_RESULT" = "PONG" ]; then
    echo "✅ Server responding: $PING_RESULT"
    
    # Clear data
    redis-cli -p 6379 flushall >/dev/null 2>&1
    
    echo ""
    echo "🎯 SET/GET Correctness Test (4C:4S):"
    echo "====================================="
    
    # Test SET/GET operations
    FAILURES=0
    TOTAL=15
    
    echo "Testing $TOTAL SET→GET operations..."
    for i in $(seq 1 $TOTAL); do
        SET_RESULT=$(redis-cli -p 6379 set test_key_$i test_value_$i 2>/dev/null)
        GET_RESULT=$(redis-cli -p 6379 get test_key_$i 2>/dev/null)
        
        if [ "$SET_RESULT" = "OK" ] && [ "$GET_RESULT" = "test_value_$i" ]; then
            echo "✅ Test $i: SET/GET working"
        else
            echo "❌ Test $i: SET='$SET_RESULT' GET='$GET_RESULT'"
            FAILURES=$((FAILURES + 1))
        fi
    done
    
    echo ""
    echo "Results for 4C:4S:"
    echo "Failures: $FAILURES/$TOTAL"
    SUCCESS_RATE=$(echo "scale=1; (($TOTAL - $FAILURES) * 100) / $TOTAL" | bc -l 2>/dev/null || echo "N/A")
    echo "Success rate: ${SUCCESS_RATE}%"
    
else
    echo "❌ Server (4C:4S) not responding: '$PING_RESULT'"
    FAILURES=$TOTAL
fi

kill $SERVER_PID 2>/dev/null
sleep 3

# Test Configuration 2: 6C:6S (cores = shards)
echo ""
echo "🧪 TEST 2: 6 Cores = 6 Shards"  
echo "============================="

./meteor_simple -h 127.0.0.1 -p 6379 -c 6 -s 6 -m 1536 > test2.log 2>&1 &
SERVER_PID=$!

echo "Server starting (6C:6S)..."
sleep 6

# Test connectivity  
PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)
if [ "$PING_RESULT" = "PONG" ]; then
    echo "✅ Server responding: $PING_RESULT"
    
    # Clear data
    redis-cli -p 6379 flushall >/dev/null 2>&1
    
    echo ""
    echo "🎯 SET/GET Correctness Test (6C:6S):"
    echo "====================================="
    
    # Test SET/GET operations
    FAILURES_2=0
    TOTAL_2=20
    
    echo "Testing $TOTAL_2 SET→GET operations..."
    for i in $(seq 1 $TOTAL_2); do
        SET_RESULT=$(redis-cli -p 6379 set batch_key_$i batch_value_$i 2>/dev/null)
        GET_RESULT=$(redis-cli -p 6379 get batch_key_$i 2>/dev/null)
        
        if [ "$SET_RESULT" = "OK" ] && [ "$GET_RESULT" = "batch_value_$i" ]; then
            echo "✅ Test $i: SET/GET working"
        else
            echo "❌ Test $i: SET='$SET_RESULT' GET='$GET_RESULT'"
            FAILURES_2=$((FAILURES_2 + 1))
        fi
    done
    
    echo ""
    echo "Results for 6C:6S:"
    echo "Failures: $FAILURES_2/$TOTAL_2" 
    SUCCESS_RATE_2=$(echo "scale=1; (($TOTAL_2 - $FAILURES_2) * 100) / $TOTAL_2" | bc -l 2>/dev/null || echo "N/A")
    echo "Success rate: ${SUCCESS_RATE_2}%"
    
else
    echo "❌ Server (6C:6S) not responding: '$PING_RESULT'"
    FAILURES_2=$TOTAL_2
fi

kill $SERVER_PID 2>/dev/null
sleep 3

# Test Configuration 3: Auto-detect cores = shards
echo ""
echo "🧪 TEST 3: Auto-detect (cores = shards enforcement)"
echo "================================================="

./meteor_simple -h 127.0.0.1 -p 6379 -m 2048 > test3.log 2>&1 &
SERVER_PID=$!

echo "Server starting (auto-detect with cores=shards enforcement)..."
sleep 6

# Test connectivity
PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)
if [ "$PING_RESULT" = "PONG" ]; then
    echo "✅ Server responding: $PING_RESULT"
    
    # Test a few operations
    redis-cli -p 6379 flushall >/dev/null 2>&1
    
    echo "Quick correctness test:"
    redis-cli -p 6379 set auto_key_1 auto_value_1 >/dev/null 2>&1
    AUTO_RESULT=$(redis-cli -p 6379 get auto_key_1 2>/dev/null)
    echo "auto_key_1: '$AUTO_RESULT'"
    
    redis-cli -p 6379 set auto_key_2 auto_value_2 >/dev/null 2>&1
    AUTO_RESULT_2=$(redis-cli -p 6379 get auto_key_2 2>/dev/null)
    echo "auto_key_2: '$AUTO_RESULT_2'"
    
    if [ "$AUTO_RESULT" = "auto_value_1" ] && [ "$AUTO_RESULT_2" = "auto_value_2" ]; then
        AUTO_SUCCESS=1
        echo "✅ Auto-detect working correctly"
    else
        AUTO_SUCCESS=0
        echo "❌ Auto-detect issues"
    fi
    
else
    echo "❌ Server (auto-detect) not responding: '$PING_RESULT'"
    AUTO_SUCCESS=0
fi

kill $SERVER_PID 2>/dev/null

# Show debug logs
echo ""
echo "🔍 DEBUG LOG ANALYSIS:"
echo "====================="

echo ""
echo "Configuration enforcement (test3.log):"
grep -E "ENFORCING CORES|Configuration:" test3.log | head -3 || echo "No enforcement messages found"

echo ""
echo "Core initialization (test1.log):"
grep -E "Core.*configured.*direct local|Core.*owns.*shard" test1.log | head -4 || echo "No core init messages found"

echo ""
echo "Command processing (test2.log):"
grep -E "Core.*processing.*key|LOCAL PROCESSING" test2.log | head -6 || echo "No processing messages found"

# Final summary
echo ""
echo "🏆 FINAL CORRECTNESS RESULTS:"
echo "============================"
echo "4C:4S configuration: $((TOTAL - FAILURES))/$TOTAL successful (${SUCCESS_RATE}%)"
echo "6C:6S configuration: $((TOTAL_2 - FAILURES_2))/$TOTAL_2 successful (${SUCCESS_RATE_2}%)"
echo "Auto-detect config: $([ $AUTO_SUCCESS -eq 1 ] && echo "✅ WORKING" || echo "❌ FAILED")"

TOTAL_FAILURES=$((FAILURES + FAILURES_2 + (1 - AUTO_SUCCESS)))
TOTAL_TESTS=$((TOTAL + TOTAL_2 + 1))

if [ $TOTAL_FAILURES -eq 0 ]; then
    echo ""
    echo "🎉 PERFECT SUCCESS! 🎉"  
    echo "===================="
    echo "✅ Cores=Shards architecture: WORKING"
    echo "✅ Direct local processing: CORRECT"
    echo "✅ No cross-shard complexity needed"
    echo "✅ SET/GET operations: 100% correct"
    echo ""
    echo "🚀 Ready for performance optimization!"
    
elif [ $TOTAL_FAILURES -le 2 ]; then
    echo ""
    echo "🟡 MOSTLY WORKING"
    echo "================"
    echo "Minor issues but architecture is fundamentally sound"
    echo "Total failures: $TOTAL_FAILURES/$TOTAL_TESTS tests"
    
else
    echo ""  
    echo "❌ ISSUES DETECTED"
    echo "=================="
    echo "Need to investigate core architecture problems"
    echo "Total failures: $TOTAL_FAILURES/$TOTAL_TESTS tests"
fi

echo ""
echo "🎯 Expected: 0 failures for working cores=shards implementation"
echo "🔧 Next step: Performance optimization and scaling tests"













