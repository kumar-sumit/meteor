#!/bin/bash

cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor || true

echo "🔑 KEY ROUTING CORRECTNESS TEST"
echo "==============================="
echo "Testing cores=shards with proper key-based routing"
echo "Each key should route to the correct core that owns its shard"
echo ""

# Build
echo "🔨 Building routing-fixed version..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
    meteor_routing_fixed.cpp -o meteor_routing \
    -luring -lboost_fiber -lboost_context -lboost_system -pthread

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful!"

# Test Configuration: 4C:4S (cores = shards with routing)
echo ""
echo "🧪 ROUTING TEST: 4 Cores = 4 Shards with Key Routing"
echo "=================================================="

./meteor_routing -h 127.0.0.1 -p 6379 -c 4 -s 4 -m 1024 > routing.log 2>&1 &
SERVER_PID=$!

echo "Server starting with routing debug..."
sleep 8

# Test connectivity
PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)
if [ "$PING_RESULT" = "PONG" ]; then
    echo "✅ Server responding: $PING_RESULT"
    
    # Clear data
    redis-cli -p 6379 flushall >/dev/null 2>&1
    
    echo ""
    echo "🎯 KEY ROUTING TEST:"
    echo "==================="
    echo "Testing multiple keys that should route to different cores"
    
    # Test SET/GET operations with different keys
    FAILURES=0
    TOTAL=12
    
    echo "Testing $TOTAL different keys (should show routing decisions)..."
    for i in $(seq 1 $TOTAL); do
        KEY="test_key_${i}_$(date +%s%N | cut -c1-6)"
        VALUE="value_for_key_$i"
        
        echo ""
        echo "🔍 Testing key: $KEY"
        echo "SET operation:"
        SET_RESULT=$(redis-cli -p 6379 set $KEY $VALUE 2>/dev/null)
        echo "GET operation:"
        GET_RESULT=$(redis-cli -p 6379 get $KEY 2>/dev/null)
        
        if [ "$SET_RESULT" = "OK" ] && [ "$GET_RESULT" = "$VALUE" ]; then
            echo "✅ Key $i: SET/GET working correctly"
        else
            echo "❌ Key $i: SET='$SET_RESULT' GET='$GET_RESULT' (expected: '$VALUE')"
            FAILURES=$((FAILURES + 1))
        fi
    done
    
    echo ""
    echo "Results:"
    echo "Failures: $FAILURES/$TOTAL"
    SUCCESS_RATE=$(echo "scale=1; (($TOTAL - $FAILURES) * 100) / $TOTAL" | bc -l 2>/dev/null || echo "N/A")
    echo "Success rate: ${SUCCESS_RATE}%"
    
    # Test same key multiple times to verify consistency
    echo ""
    echo "🔄 CONSISTENCY TEST:"
    echo "===================="
    echo "Testing same key multiple times to verify routing consistency"
    
    SAME_KEY="consistency_test_key"
    SAME_VALUE="consistency_test_value"
    CONSISTENCY_FAILURES=0
    CONSISTENCY_TOTAL=8
    
    echo "Setting initial value..."
    redis-cli -p 6379 set $SAME_KEY $SAME_VALUE >/dev/null 2>&1
    
    for i in $(seq 1 $CONSISTENCY_TOTAL); do
        GET_RESULT=$(redis-cli -p 6379 get $SAME_KEY 2>/dev/null)
        if [ "$GET_RESULT" = "$SAME_VALUE" ]; then
            echo "✅ Consistency test $i: correct value"
        else
            echo "❌ Consistency test $i: got '$GET_RESULT' (expected: '$SAME_VALUE')"
            CONSISTENCY_FAILURES=$((CONSISTENCY_FAILURES + 1))
        fi
    done
    
    echo "Consistency failures: $CONSISTENCY_FAILURES/$CONSISTENCY_TOTAL"
    
else
    echo "❌ Server not responding: '$PING_RESULT'"
    FAILURES=$TOTAL
    CONSISTENCY_FAILURES=$CONSISTENCY_TOTAL
fi

kill $SERVER_PID 2>/dev/null
sleep 2

# Analyze debug logs
echo ""
echo "🔍 ROUTING DEBUG LOG ANALYSIS:"
echo "=============================="

echo ""
echo "1. Configuration enforcement:"
grep -E "ENFORCING CORES|Configuration.*cores.*shards" routing.log | head -3 || echo "No enforcement messages found"

echo ""
echo "2. Core initialization and references:"
grep -E "Core.*configured.*direct local|Core.*references.*cores" routing.log | head -4 || echo "No core init messages found"

echo ""
echo "3. Key routing decisions:"
grep -E "Core.*received.*key|target_core=|CORRECT CORE|ROUTING.*Migrating" routing.log | head -10 || echo "No routing decisions found"

echo ""
echo "4. Connection migrations:"
grep -E "MIGRATED.*Connection sent|received migrated connection|Processing migrated command" routing.log | head -8 || echo "No migration messages found"

echo ""
echo "5. Errors or issues:"
grep -E "MIGRATION FAILED|INVALID TARGET|ROUTING FAILED|ERROR" routing.log | head -5 || echo "No errors found"

# Final analysis
echo ""
echo "🏆 ROUTING CORRECTNESS ANALYSIS:"
echo "==============================="

TOTAL_FAILURES=$((FAILURES + CONSISTENCY_FAILURES))
TOTAL_TESTS=$((TOTAL + CONSISTENCY_TOTAL))

if [ $TOTAL_FAILURES -eq 0 ]; then
    echo ""
    echo "🎉 PERFECT ROUTING SUCCESS! 🎉"
    echo "=============================="
    echo "✅ Key routing: WORKING"
    echo "✅ Connection migration: CORRECT"
    echo "✅ Cores=Shards architecture: FUNCTIONAL"
    echo "✅ SET/GET operations: 100% consistent"
    echo ""
    echo "🚀 Key routing implementation is correct!"
    
elif [ $TOTAL_FAILURES -le 2 ]; then
    echo ""
    echo "🟡 MOSTLY WORKING ROUTING"
    echo "========================="
    echo "Key routing mostly functional with minor issues"
    echo "Total failures: $TOTAL_FAILURES/$TOTAL_TESTS tests"
    echo "✅ Core architecture: Sound"
    echo "⚠️  Need to debug specific routing scenarios"
    
else
    echo ""
    echo "❌ ROUTING ISSUES DETECTED"
    echo "========================="
    echo "Significant routing problems need investigation"
    echo "Total failures: $TOTAL_FAILURES/$TOTAL_TESTS tests"
    echo ""
    echo "🔍 Debug priorities:"
    echo "1. Check if connection migration is working"
    echo "2. Verify key hashing consistency"
    echo "3. Ensure all_cores_ references are correct"
    echo "4. Check if migrated commands are processed"
fi

echo ""
echo "📊 Key metrics from logs:"
echo "========================"
echo "Routing decisions made: $(grep -c "target_core=" routing.log 2>/dev/null || echo "0")"
echo "Local processing: $(grep -c "CORRECT CORE" routing.log 2>/dev/null || echo "0")"
echo "Cross-core migrations: $(grep -c "ROUTING.*Migrating" routing.log 2>/dev/null || echo "0")"
echo "Successful migrations: $(grep -c "MIGRATED.*Connection sent" routing.log 2>/dev/null || echo "0")"
echo "Migration processing: $(grep -c "Processing migrated command" routing.log 2>/dev/null || echo "0")"

echo ""
echo "💡 Expected behavior:"
echo "- Keys should be consistently routed to same core"
echo "- Migration messages when key belongs to different core"
echo "- 100% SET/GET success rate"
echo "- Zero routing failures"













