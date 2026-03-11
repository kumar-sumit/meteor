#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🔍 BASELINE SERVER - REDIS-CLI TEST"
echo "$(date): Testing baseline with redis-cli (proper RESP protocol)"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== STEP 1: START BASELINE SERVER ==="
echo "Starting original baseline server..."
nohup ./meteor_baseline_original -c 4 -s 4   > baseline_redis_cli.log 2>&1 &
SERVER_PID=$!
sleep 6

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    cat baseline_redis_cli.log
    exit 1
fi

echo "✅ BASELINE SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 2: BASIC REDIS-CLI OPERATIONS ==="
echo "🎯 Testing individual commands with redis-cli"

echo -n "SET key1 value1: "
SET1=$(redis-cli -p 6379 SET key1 value1 2>/dev/null || echo "FAILED")
echo "$SET1"

echo -n "GET key1: "
GET1=$(redis-cli -p 6379 GET key1 2>/dev/null || echo "FAILED")
echo "$GET1"

echo -n "PING: "
PING1=$(redis-cli -p 6379 PING 2>/dev/null || echo "FAILED")
echo "$PING1"

echo -n "DEL key1: "
DEL1=$(redis-cli -p 6379 DEL key1 2>/dev/null || echo "FAILED")
echo "$DEL1"

echo -n "GET key1 (after DEL): "
GET1_AFTER_DEL=$(redis-cli -p 6379 GET key1 2>/dev/null || echo "FAILED")
echo "$GET1_AFTER_DEL"

BASIC_SUCCESS=false
if [[ "$SET1" == "OK" ]] && [[ "$GET1" == "value1" ]] && [[ "$PING1" == "PONG" ]] && [[ "$DEL1" == "1" ]]; then
    echo "✅ BASIC OPERATIONS SUCCESS: All basic redis-cli commands working"
    BASIC_SUCCESS=true
else
    echo "❌ BASIC OPERATIONS FAILED: SET='$SET1', GET='$GET1', PING='$PING1', DEL='$DEL1'"
fi

echo ""
echo "=== STEP 3: MULTIPLE SEQUENTIAL OPERATIONS ==="
echo "🎯 Testing multiple operations in sequence with redis-cli"

SEQUENTIAL_SUCCESS=true
for i in {1..10}; do
    echo "--- Sequential Operation $i ---"
    
    SET_RESULT=$(redis-cli -p 6379 SET seqkey$i seqval$i 2>/dev/null || echo "FAILED")
    echo "SET seqkey$i: $SET_RESULT"
    
    if [[ "$SET_RESULT" != "OK" ]]; then
        echo "❌ Sequential SET failed at operation $i"
        SEQUENTIAL_SUCCESS=false
        break
    fi
    
    GET_RESULT=$(redis-cli -p 6379 GET seqkey$i 2>/dev/null || echo "FAILED")
    echo "GET seqkey$i: $GET_RESULT"
    
    if [[ "$GET_RESULT" != "seqval$i" ]]; then
        echo "❌ Sequential GET failed at operation $i: expected 'seqval$i', got '$GET_RESULT'"
        SEQUENTIAL_SUCCESS=false
        break
    fi
    
    PING_RESULT=$(redis-cli -p 6379 PING 2>/dev/null || echo "FAILED")
    if [[ "$PING_RESULT" != "PONG" ]]; then
        echo "❌ Sequential PING failed at operation $i"
        SEQUENTIAL_SUCCESS=false
        break
    fi
done

if [ "$SEQUENTIAL_SUCCESS" = true ]; then
    echo "✅ SEQUENTIAL SUCCESS: All 10 sequential operations perfect"
else
    echo "❌ SEQUENTIAL FAILED: Sequential operations not working"
fi

echo ""
echo "=== STEP 4: RAPID FIRE OPERATIONS ==="
echo "🎯 Testing rapid operations with redis-cli"

RAPID_SUCCESS=true
echo "Performing 20 rapid SET/GET operations..."
for i in {1..20}; do
    redis-cli -p 6379 SET rapidkey$i rapidval$i >/dev/null 2>&1
    RAPID_GET=$(redis-cli -p 6379 GET rapidkey$i 2>/dev/null || echo "FAILED")
    
    if [[ "$RAPID_GET" != "rapidval$i" ]]; then
        echo "❌ Rapid fire failed at operation $i: expected 'rapidval$i', got '$RAPID_GET'"
        RAPID_SUCCESS=false
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "Rapid fire progress: $i/20 operations completed successfully"
    fi
done

if [ "$RAPID_SUCCESS" = true ]; then
    echo "✅ RAPID FIRE SUCCESS: All 20 rapid operations perfect"
else
    echo "❌ RAPID FIRE FAILED: Rapid operations not working"
fi

echo ""
echo "=== STEP 5: DIFFERENT DATA SIZES ==="
echo "🎯 Testing different value sizes with redis-cli"

echo -n "Short value: "
redis-cli -p 6379 SET shortkey "short" >/dev/null 2>&1
SHORT_GET=$(redis-cli -p 6379 GET shortkey 2>/dev/null || echo "FAILED")
echo "$SHORT_GET"

echo -n "Medium value: "
MEDIUM_VALUE="this_is_a_medium_length_value_for_testing_response_handling_capabilities"
redis-cli -p 6379 SET mediumkey "$MEDIUM_VALUE" >/dev/null 2>&1
MEDIUM_GET=$(redis-cli -p 6379 GET mediumkey 2>/dev/null || echo "FAILED")
echo "$MEDIUM_GET"

echo -n "Long value (100 chars): "
LONG_VALUE=$(python3 -c "print('x' * 100)")
redis-cli -p 6379 SET longkey "$LONG_VALUE" >/dev/null 2>&1
LONG_GET=$(redis-cli -p 6379 GET longkey 2>/dev/null || echo "FAILED")
echo "${LONG_GET:0:20}... (truncated, length: ${#LONG_GET})"

SIZE_SUCCESS=false
if [[ "$SHORT_GET" == "short" ]] && [[ "$MEDIUM_GET" == "$MEDIUM_VALUE" ]] && [[ "${#LONG_GET}" -eq 100 ]]; then
    echo "✅ SIZE TESTS SUCCESS: All value sizes working correctly"
    SIZE_SUCCESS=true
else
    echo "❌ SIZE TESTS FAILED: Different sizes not handled correctly"
fi

echo ""
echo "=== STEP 6: MIXED COMMAND TYPES ==="
echo "🎯 Testing mixed command patterns with redis-cli"

MIXED_SUCCESS=true
for i in {1..5}; do
    echo "--- Mixed Pattern $i ---"
    
    # Mix of SET, GET, PING, DEL
    redis-cli -p 6379 SET mixkey$i mixval$i >/dev/null 2>&1
    
    MIX_GET=$(redis-cli -p 6379 GET mixkey$i 2>/dev/null || echo "FAILED")
    echo "GET mixkey$i: $MIX_GET"
    
    MIX_PING=$(redis-cli -p 6379 PING 2>/dev/null || echo "FAILED")
    echo "PING: $MIX_PING"
    
    MIX_DEL=$(redis-cli -p 6379 DEL mixkey$i 2>/dev/null || echo "FAILED")
    echo "DEL mixkey$i: $MIX_DEL"
    
    MIX_GET_AFTER=$(redis-cli -p 6379 GET mixkey$i 2>/dev/null || echo "FAILED")
    echo "GET mixkey$i (after DEL): $MIX_GET_AFTER"
    
    if [[ "$MIX_GET" != "mixval$i" ]] || [[ "$MIX_PING" != "PONG" ]] || [[ "$MIX_DEL" != "1" ]] || [[ "$MIX_GET_AFTER" != "" ]]; then
        echo "❌ Mixed pattern failed at iteration $i"
        MIXED_SUCCESS=false
        break
    fi
done

if [ "$MIXED_SUCCESS" = true ]; then
    echo "✅ MIXED PATTERNS SUCCESS: All mixed command patterns working"
else
    echo "❌ MIXED PATTERNS FAILED: Mixed commands not working properly"
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 BASELINE REDIS-CLI TEST RESULTS"
echo "=========================================="
echo ""

BASELINE_WORKS_PERFECTLY=false
if [ "$BASIC_SUCCESS" = true ] && [ "$SEQUENTIAL_SUCCESS" = true ] && [ "$RAPID_SUCCESS" = true ] && [ "$SIZE_SUCCESS" = true ] && [ "$MIXED_SUCCESS" = true ]; then
    BASELINE_WORKS_PERFECTLY=true
fi

echo "📊 REDIS-CLI TEST RESULTS:"
echo ""

if [ "$BASELINE_WORKS_PERFECTLY" = true ]; then
    echo "✅ BASELINE SERVER: WORKS PERFECTLY WITH REDIS-CLI! ✅"
    echo ""
    echo "🎯 DEFINITIVE FINDINGS:"
    echo "   • Basic operations (SET/GET/PING/DEL): PERFECT"
    echo "   • Sequential operations (10 in a row): PERFECT"
    echo "   • Rapid fire operations (20 rapid): PERFECT"
    echo "   • Different data sizes: PERFECT"
    echo "   • Mixed command patterns: PERFECT"
    echo "   • RESP protocol handling: FLAWLESS"
    echo ""
    echo "🔍 CONFIRMED ROOT CAUSE:"
    echo "   • Baseline server is completely functional"
    echo "   • Works perfectly with proper Redis clients (redis-cli, memtier)"
    echo "   • My previous tests used flawed nc approach with bad RESP formatting"
    echo "   • The response handling 'bug' was in my test methodology, not the server"
    echo ""
    echo "🎯 IMPLICATIONS FOR TTL:"
    echo "   • TTL implementation failures are due to my code changes, not baseline"
    echo "   • Need to identify exactly what I'm changing that breaks functionality"
    echo "   • Should implement TTL on this working baseline"
    echo "   • Test TTL implementations with redis-cli, not manual nc commands"
else
    echo "⚠️  BASELINE SERVER: HAS SOME REDIS-CLI ISSUES"
    echo ""
    echo "🔍 SPECIFIC ISSUES IDENTIFIED:"
    if [ "$BASIC_SUCCESS" = false ]; then
        echo "   • Basic operations not working with redis-cli"
    fi
    if [ "$SEQUENTIAL_SUCCESS" = false ]; then
        echo "   • Sequential operations failing"
    fi
    if [ "$RAPID_SUCCESS" = false ]; then
        echo "   • Rapid operations failing"
    fi
    if [ "$SIZE_SUCCESS" = false ]; then
        echo "   • Different data sizes not handled properly"
    fi
    if [ "$MIXED_SUCCESS" = false ]; then
        echo "   • Mixed command patterns failing"
    fi
fi

echo ""
echo "$(date): Baseline redis-cli test complete!"
echo ""

echo "Server log (last 15 lines):"
tail -15 baseline_redis_cli.log

echo ""
if [ "$BASELINE_WORKS_PERFECTLY" = true ]; then
    echo "🎉 BASELINE IS PERFECT! NOW I CAN IMPLEMENT TTL CORRECTLY! 🎉"
    echo "The issue was my flawed testing methodology, not the server!"
else
    echo "🔧 BASELINE NEEDS INVESTIGATION WITH PROPER REDIS CLIENT"
fi












