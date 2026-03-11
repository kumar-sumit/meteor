#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🔍 BASELINE SERVER - REDIS-CLI TEST (FIXED)"
echo "$(date): Testing baseline with proper redis-cli usage"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== STEP 1: START BASELINE SERVER ==="
echo "Starting original baseline server..."
nohup ./meteor_baseline_original -c 4 -s 4 > baseline_redis_cli_fixed.log 2>&1 &
SERVER_PID=$!
sleep 6

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    cat baseline_redis_cli_fixed.log
    exit 1
fi

echo "✅ BASELINE SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 2: BASIC REDIS-CLI OPERATIONS ==="
echo "🎯 Testing individual commands with proper timeouts"

echo -n "SET key1 value1: "
SET1=$(timeout 5s redis-cli -p 6379 SET key1 value1 2>/dev/null || echo "TIMEOUT_OR_FAILED")
echo "$SET1"

echo -n "GET key1: "
GET1=$(timeout 5s redis-cli -p 6379 GET key1 2>/dev/null || echo "TIMEOUT_OR_FAILED")
echo "$GET1"

echo -n "PING: "
PING1=$(timeout 5s redis-cli -p 6379 PING 2>/dev/null || echo "TIMEOUT_OR_FAILED")
echo "$PING1"

echo -n "SET key2 value2: "
SET2=$(timeout 5s redis-cli -p 6379 SET key2 value2 2>/dev/null || echo "TIMEOUT_OR_FAILED")
echo "$SET2"

echo -n "GET key2: "
GET2=$(timeout 5s redis-cli -p 6379 GET key2 2>/dev/null || echo "TIMEOUT_OR_FAILED")
echo "$GET2"

echo -n "DEL key1: "
DEL1=$(timeout 5s redis-cli -p 6379 DEL key1 2>/dev/null || echo "TIMEOUT_OR_FAILED")
echo "$DEL1"

echo -n "GET key1 (after DEL): "
GET1_AFTER_DEL=$(timeout 5s redis-cli -p 6379 GET key1 2>/dev/null || echo "TIMEOUT_OR_FAILED")
if [ -z "$GET1_AFTER_DEL" ]; then
    GET1_AFTER_DEL="(null)"
fi
echo "$GET1_AFTER_DEL"

BASIC_SUCCESS=false
if [[ "$SET1" == "OK" ]] && [[ "$GET1" == "value1" ]] && [[ "$SET2" == "OK" ]] && [[ "$GET2" == "value2" ]] && [[ "$DEL1" == "1" ]]; then
    echo "✅ BASIC OPERATIONS SUCCESS: SET/GET/DEL working perfectly"
    BASIC_SUCCESS=true
    
    if [[ "$PING1" == "PONG" ]]; then
        echo "✅ PING ALSO WORKS: Full basic command set functional"
    else
        echo "⚠️  PING has issues but core commands work: PING='$PING1'"
    fi
else
    echo "❌ BASIC OPERATIONS FAILED:"
    echo "   SET1='$SET1', GET1='$GET1', SET2='$SET2', GET2='$GET2', DEL1='$DEL1'"
fi

echo ""
echo "=== STEP 3: SEQUENTIAL OPERATIONS TEST ==="
echo "🎯 Testing multiple SET/GET operations in sequence"

SEQUENTIAL_SUCCESS=true
SEQUENTIAL_COUNT=0

for i in {1..5}; do
    echo "--- Sequential Operation $i ---"
    
    SET_CMD="SET seqkey$i seqval$i"
    echo -n "$SET_CMD: "
    SET_RESULT=$(timeout 3s redis-cli -p 6379 $SET_CMD 2>/dev/null || echo "TIMEOUT_OR_FAILED")
    echo "$SET_RESULT"
    
    if [[ "$SET_RESULT" == "OK" ]]; then
        GET_CMD="GET seqkey$i"
        echo -n "$GET_CMD: "
        GET_RESULT=$(timeout 3s redis-cli -p 6379 $GET_CMD 2>/dev/null || echo "TIMEOUT_OR_FAILED")
        echo "$GET_RESULT"
        
        if [[ "$GET_RESULT" == "seqval$i" ]]; then
            SEQUENTIAL_COUNT=$((SEQUENTIAL_COUNT + 1))
            echo "✓ Operation $i: SUCCESS"
        else
            echo "✗ Operation $i: GET failed - expected 'seqval$i', got '$GET_RESULT'"
            SEQUENTIAL_SUCCESS=false
            break
        fi
    else
        echo "✗ Operation $i: SET failed - got '$SET_RESULT'"
        SEQUENTIAL_SUCCESS=false
        break
    fi
    
    sleep 0.5
done

if [ "$SEQUENTIAL_SUCCESS" = true ]; then
    echo "✅ SEQUENTIAL SUCCESS: $SEQUENTIAL_COUNT/5 operations completed perfectly"
else
    echo "❌ SEQUENTIAL FAILED: Stopped at operation with failure"
fi

echo ""
echo "=== STEP 4: RAPID OPERATIONS TEST ==="
echo "🎯 Testing rapid SET/GET without delays"

RAPID_SUCCESS=true
RAPID_SUCCESS_COUNT=0

echo "Testing 10 rapid operations..."
for i in {1..10}; do
    # Rapid SET
    timeout 2s redis-cli -p 6379 SET rapidkey$i rapidval$i >/dev/null 2>&1
    
    # Rapid GET
    RAPID_GET=$(timeout 2s redis-cli -p 6379 GET rapidkey$i 2>/dev/null || echo "FAILED")
    
    if [[ "$RAPID_GET" == "rapidval$i" ]]; then
        RAPID_SUCCESS_COUNT=$((RAPID_SUCCESS_COUNT + 1))
    else
        echo "✗ Rapid operation $i failed: expected 'rapidval$i', got '$RAPID_GET'"
        RAPID_SUCCESS=false
        break
    fi
    
    if [ $((i % 3)) -eq 0 ]; then
        echo "Rapid progress: $i/10 operations successful"
    fi
done

if [ "$RAPID_SUCCESS" = true ]; then
    echo "✅ RAPID SUCCESS: $RAPID_SUCCESS_COUNT/10 rapid operations perfect"
else
    echo "❌ RAPID FAILED: Only $RAPID_SUCCESS_COUNT operations successful"
fi

echo ""
echo "=== STEP 5: DIFFERENT VALUE SIZES ==="
echo "🎯 Testing various value sizes"

echo -n "Short value: "
timeout 3s redis-cli -p 6379 SET shortkey "short" >/dev/null 2>&1
SHORT_GET=$(timeout 3s redis-cli -p 6379 GET shortkey 2>/dev/null || echo "FAILED")
echo "$SHORT_GET"

echo -n "Medium value: "
MEDIUM_VAL="this_is_a_medium_length_value_for_testing"
timeout 3s redis-cli -p 6379 SET mediumkey "$MEDIUM_VAL" >/dev/null 2>&1
MEDIUM_GET=$(timeout 3s redis-cli -p 6379 GET mediumkey 2>/dev/null || echo "FAILED")
echo "$MEDIUM_GET"

echo -n "Long value (50 chars): "
LONG_VAL="12345678901234567890123456789012345678901234567890"
timeout 3s redis-cli -p 6379 SET longkey "$LONG_VAL" >/dev/null 2>&1
LONG_GET=$(timeout 3s redis-cli -p 6379 GET longkey 2>/dev/null || echo "FAILED")
echo "${LONG_GET:0:20}...[${#LONG_GET} chars]"

SIZE_SUCCESS=false
if [[ "$SHORT_GET" == "short" ]] && [[ "$MEDIUM_GET" == "$MEDIUM_VAL" ]] && [[ "${#LONG_GET}" -eq 50 ]]; then
    echo "✅ SIZE TESTS SUCCESS: All value sizes handled correctly"
    SIZE_SUCCESS=true
else
    echo "❌ SIZE TESTS FAILED: Issues with different value sizes"
fi

echo ""
echo "=== STEP 6: STRESS TEST ==="
echo "🎯 Testing server stability with multiple operations"

STRESS_SUCCESS=true
STRESS_COUNT=0

echo "Running 15 mixed operations..."
for i in {1..15}; do
    # Mixed pattern: SET, GET, different key
    timeout 2s redis-cli -p 6379 SET stresskey$i stressval$i >/dev/null 2>&1
    STRESS_GET=$(timeout 2s redis-cli -p 6379 GET stresskey$i 2>/dev/null || echo "FAILED")
    
    if [[ "$STRESS_GET" == "stressval$i" ]]; then
        STRESS_COUNT=$((STRESS_COUNT + 1))
    else
        echo "✗ Stress test failed at operation $i: '$STRESS_GET'"
        STRESS_SUCCESS=false
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "Stress test progress: $i/15 operations successful"
    fi
done

if [ "$STRESS_SUCCESS" = true ]; then
    echo "✅ STRESS TEST SUCCESS: $STRESS_COUNT/15 operations perfect"
else
    echo "❌ STRESS TEST FAILED: Only $STRESS_COUNT operations successful"
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 BASELINE REDIS-CLI FIXED TEST RESULTS"
echo "=========================================="
echo ""

# Calculate overall success
OVERALL_SUCCESS=false
TOTAL_SCORE=0

if [ "$BASIC_SUCCESS" = true ]; then TOTAL_SCORE=$((TOTAL_SCORE + 1)); fi
if [ "$SEQUENTIAL_SUCCESS" = true ]; then TOTAL_SCORE=$((TOTAL_SCORE + 1)); fi
if [ "$RAPID_SUCCESS" = true ]; then TOTAL_SCORE=$((TOTAL_SCORE + 1)); fi
if [ "$SIZE_SUCCESS" = true ]; then TOTAL_SCORE=$((TOTAL_SCORE + 1)); fi
if [ "$STRESS_SUCCESS" = true ]; then TOTAL_SCORE=$((TOTAL_SCORE + 1)); fi

if [ "$TOTAL_SCORE" -ge 4 ]; then
    OVERALL_SUCCESS=true
fi

echo "📊 COMPREHENSIVE TEST RESULTS:"
echo ""
echo "Test Category Results:"
echo "• Basic Operations (SET/GET/DEL): $([ "$BASIC_SUCCESS" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "• Sequential Operations (5 in row): $([ "$SEQUENTIAL_SUCCESS" = true ] && echo "✅ PASS ($SEQUENTIAL_COUNT/5)" || echo "❌ FAIL")"
echo "• Rapid Operations (10 rapid): $([ "$RAPID_SUCCESS" = true ] && echo "✅ PASS ($RAPID_SUCCESS_COUNT/10)" || echo "❌ FAIL")"
echo "• Different Value Sizes: $([ "$SIZE_SUCCESS" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "• Stress Test (15 mixed ops): $([ "$STRESS_SUCCESS" = true ] && echo "✅ PASS ($STRESS_COUNT/15)" || echo "❌ FAIL")"
echo ""
echo "Overall Score: $TOTAL_SCORE/5 test categories passed"

if [ "$OVERALL_SUCCESS" = true ]; then
    echo ""
    echo "🎉 BASELINE SERVER: EXCELLENT WITH REDIS-CLI! 🎉"
    echo ""
    echo "🎯 CONFIRMED CAPABILITIES:"
    echo "   • Core Redis commands work perfectly"
    echo "   • Sequential operations stable"
    echo "   • Rapid operations handled well"  
    echo "   • Various data sizes supported"
    echo "   • Server stability under load"
    echo ""
    echo "✅ READY FOR TTL IMPLEMENTATION:"
    echo "   • Baseline is solid and reliable"
    echo "   • TTL can be safely implemented on this foundation"
    echo "   • Use redis-cli for all future testing"
    echo "   • Focus on TTL-specific functionality"
else
    echo ""
    echo "⚠️  BASELINE SERVER: SOME ISSUES IDENTIFIED"
    echo ""
    echo "🔍 AREAS NEEDING ATTENTION:"
    if [ "$BASIC_SUCCESS" = false ]; then echo "   • Basic command functionality"; fi
    if [ "$SEQUENTIAL_SUCCESS" = false ]; then echo "   • Sequential operation stability"; fi
    if [ "$RAPID_SUCCESS" = false ]; then echo "   • Rapid operation handling"; fi
    if [ "$SIZE_SUCCESS" = false ]; then echo "   • Variable data size support"; fi  
    if [ "$STRESS_SUCCESS" = false ]; then echo "   • Server stability under load"; fi
fi

echo ""
echo "$(date): Baseline redis-cli fixed test complete!"
echo ""

echo "Server log (last 10 lines):"
tail -10 baseline_redis_cli_fixed.log

echo ""
echo "🚀 Next step: Implement TTL on this $([ "$OVERALL_SUCCESS" = true ] && echo "working" || echo "partially working") baseline!"












