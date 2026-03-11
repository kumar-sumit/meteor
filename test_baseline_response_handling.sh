#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🔍 BASELINE SERVER RESPONSE HANDLING TEST"
echo "$(date): Testing original baseline for response handling issues"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== STEP 1: BUILD ORIGINAL BASELINE SERVER ==="
export TMPDIR=/mnt/externalDisk/meteor/tmp_compile
echo "Compiling meteor_deterministic_core_affinity.cpp (original baseline)..."

g++ -std=c++20 -O3 -march=native -DBOOST_FIBER_NO_EXCEPTIONS -pthread -pipe \
    meteor_deterministic_core_affinity.cpp -o meteor_baseline_original \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

BUILD_STATUS=$?
if [ $BUILD_STATUS -ne 0 ]; then
    echo "❌ BUILD FAILED - compilation errors detected"
    exit 1
fi

echo "✅ BUILD SUCCESSFUL - Original baseline compiled"

echo ""
echo "=== STEP 2: START BASELINE SERVER ==="
echo "Starting original baseline server..."
nohup ./meteor_baseline_original -c 4 -s 4 > baseline_original.log 2>&1 &
SERVER_PID=$!
sleep 6

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    cat baseline_original.log
    exit 1
fi

echo "✅ BASELINE SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 3: SINGLE OPERATIONS TEST ==="
echo "🎯 Testing individual commands on baseline server"

echo -n "Baseline SET key1: "
SET1_RESP=$(printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey1\r\n\$6\r\nvalue1\r\n" | timeout 5s nc -w 3 127.0.0.1 6379)
echo "$SET1_RESP"

echo -n "Baseline GET key1: "
GET1_RESP=$(printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey1\r\n" | timeout 5s nc -w 3 127.0.0.1 6379)
echo "$GET1_RESP"

echo -n "Baseline PING: "
PING_RESP=$(printf "*1\r\n\$4\r\nPING\r\n" | timeout 5s nc -w 3 127.0.0.1 6379)
echo "$PING_RESP"

echo ""
echo "=== STEP 4: MULTIPLE SEQUENTIAL OPERATIONS ==="
echo "🎯 Testing multiple operations in sequence (where my implementations fail)"

BASELINE_SUCCESS=true
for i in {1..10}; do
    echo "--- Operation $i ---"
    
    # SET
    echo -n "SET multikey$i: "
    SET_RESP=$(printf "*3\r\n\$3\r\nSET\r\n\$9\r\nmultikey$i\r\n\$9\r\nmultival$i\r\n" | timeout 3s nc -w 2 127.0.0.1 6379)
    echo "$SET_RESP"
    
    if [[ ! "$SET_RESP" == *"+OK"* ]]; then
        echo "❌ SET failed at operation $i"
        BASELINE_SUCCESS=false
        break
    fi
    
    # GET
    echo -n "GET multikey$i: "
    GET_RESP=$(printf "*2\r\n\$3\r\nGET\r\n\$9\r\nmultikey$i\r\n" | timeout 3s nc -w 2 127.0.0.1 6379)
    echo "$GET_RESP"
    
    if [[ ! "$GET_RESP" == *"multival$i"* ]]; then
        echo "❌ GET failed at operation $i: '$GET_RESP'"
        BASELINE_SUCCESS=false
        break
    fi
    
    # PING
    echo -n "PING $i: "
    PING_RESP=$(printf "*1\r\n\$4\r\nPING\r\n" | timeout 3s nc -w 2 127.0.0.1 6379)
    echo "$PING_RESP"
    
    if [[ ! "$PING_RESP" == *"+PONG"* ]]; then
        echo "❌ PING failed at operation $i: '$PING_RESP'"
        BASELINE_SUCCESS=false
        break
    fi
    
    sleep 0.5
done

if [ "$BASELINE_SUCCESS" = true ]; then
    echo "✅ MULTIPLE OPERATIONS SUCCESS: All 10 sequential operations worked perfectly"
else
    echo "❌ MULTIPLE OPERATIONS FAILED: Baseline has response handling issues"
fi

echo ""
echo "=== STEP 5: RAPID FIRE OPERATIONS ==="
echo "🎯 Testing rapid consecutive operations (stress test)"

RAPID_SUCCESS=true
for i in {1..20}; do
    # Rapid SET/GET without delays
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nrapidkey$i\r\n\$9\r\nrapidval$i\r\n" | nc -w 1 127.0.0.1 6379 > /dev/null
    RAPID_RESP=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\nrapidkey$i\r\n" | timeout 2s nc -w 1 127.0.0.1 6379)
    
    if [[ ! "$RAPID_RESP" == *"rapidval$i"* ]]; then
        echo "❌ RAPID FIRE failed at operation $i: '$RAPID_RESP'"
        RAPID_SUCCESS=false
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "Rapid fire progress: $i/20 operations completed"
    fi
done

if [ "$RAPID_SUCCESS" = true ]; then
    echo "✅ RAPID FIRE SUCCESS: All 20 rapid operations worked perfectly"
else
    echo "❌ RAPID FIRE FAILED: Baseline has issues under rapid load"
fi

echo ""
echo "=== STEP 6: DIFFERENT RESPONSE TYPES ==="
echo "🎯 Testing different response types (static vs dynamic)"

echo -n "Static PING: "
STATIC_PING=$(printf "*1\r\n\$4\r\nPING\r\n" | timeout 3s nc -w 2 127.0.0.1 6379)
echo "$STATIC_PING"

printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntestkey1\r\n\$5\r\nshort\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Dynamic GET (short): "
DYNAMIC_SHORT=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntestkey1\r\n" | timeout 3s nc -w 2 127.0.0.1 6379)
echo "$DYNAMIC_SHORT"

printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntestkey2\r\n\$50\r\nthis_is_a_very_long_value_to_test_dynamic_responses\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Dynamic GET (long): "
DYNAMIC_LONG=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntestkey2\r\n" | timeout 3s nc -w 2 127.0.0.1 6379)
echo "$DYNAMIC_LONG"

echo -n "DEL command: "
DEL_RESP=$(printf "*2\r\n\$3\r\nDEL\r\n\$8\r\ntestkey1\r\n" | timeout 3s nc -w 2 127.0.0.1 6379)
echo "$DEL_RESP"

RESPONSE_TYPES_SUCCESS=false
if [[ "$STATIC_PING" == *"+PONG"* ]] && [[ "$DYNAMIC_SHORT" == *"short"* ]] && [[ "$DYNAMIC_LONG" == *"dynamic_responses"* ]] && [[ "$DEL_RESP" == *":1"* ]]; then
    echo "✅ RESPONSE TYPES SUCCESS: All static and dynamic responses working"
    RESPONSE_TYPES_SUCCESS=true
else
    echo "❌ RESPONSE TYPES FAILED: Issues with different response types"
    echo "   PING='$STATIC_PING', Short='$DYNAMIC_SHORT'"
    echo "   Long='$DYNAMIC_LONG', DEL='$DEL_RESP'"
fi

echo ""
echo "=== STEP 7: MIXED OPERATIONS STRESS TEST ==="
echo "🎯 Testing mixed operations like my TTL implementations encounter"

MIXED_SUCCESS=true
for i in {1..15}; do
    # Mix different command types
    printf "*3\r\n\$3\r\nSET\r\n\$7\r\nmixkey$i\r\n\$7\r\nmixval$i\r\n" | nc -w 1 127.0.0.1 6379 > /dev/null
    
    GET_MIX=$(printf "*2\r\n\$3\r\nGET\r\n\$7\r\nmixkey$i\r\n" | timeout 2s nc -w 1 127.0.0.1 6379)
    PING_MIX=$(printf "*1\r\n\$4\r\nPING\r\n" | timeout 2s nc -w 1 127.0.0.1 6379)
    
    if [[ ! "$GET_MIX" == *"mixval$i"* ]] || [[ ! "$PING_MIX" == *"+PONG"* ]]; then
        echo "❌ MIXED OPERATIONS failed at iteration $i"
        echo "   GET='$GET_MIX', PING='$PING_MIX'"
        MIXED_SUCCESS=false
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "Mixed operations progress: $i/15 completed"
    fi
done

if [ "$MIXED_SUCCESS" = true ]; then
    echo "✅ MIXED OPERATIONS SUCCESS: All mixed operations worked perfectly"
else
    echo "❌ MIXED OPERATIONS FAILED: Baseline has issues with mixed commands"
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 BASELINE RESPONSE HANDLING ANALYSIS"
echo "=========================================="
echo ""

echo "📊 BASELINE SERVER ANALYSIS:"
echo ""

BASELINE_PERFECT=false
if [ "$BASELINE_SUCCESS" = true ] && [ "$RAPID_SUCCESS" = true ] && [ "$RESPONSE_TYPES_SUCCESS" = true ] && [ "$MIXED_SUCCESS" = true ]; then
    BASELINE_PERFECT=true
fi

if [ "$BASELINE_PERFECT" = true ]; then
    echo "✅ BASELINE SERVER: PERFECT ✅"
    echo ""
    echo "🎯 KEY FINDINGS:"
    echo "   • Sequential operations: PERFECT (10/10)"
    echo "   • Rapid fire operations: PERFECT (20/20)"
    echo "   • Static responses (PING): WORKING"
    echo "   • Dynamic responses (GET): WORKING"
    echo "   • Mixed operations: PERFECT (15/15)"
    echo "   • Response handling: FLAWLESS"
    echo ""
    echo "🔍 ROOT CAUSE IDENTIFICATION:"
    echo "   • Baseline server has NO response handling issues"
    echo "   • The bug is being introduced in my TTL modifications"
    echo "   • Need to identify EXACT difference causing response failure"
    echo ""
    echo "📋 NEXT STEPS:"
    echo "   1. Compare working baseline vs my modifications byte-by-byte"
    echo "   2. Identify the specific change breaking dynamic responses"
    echo "   3. Fix the modification without affecting response handling"
    echo "   4. Then implement TTL correctly"
else
    echo "⚠️  BASELINE SERVER: HAS ISSUES"
    echo ""
    echo "🔍 BASELINE PROBLEMS IDENTIFIED:"
    if [ "$BASELINE_SUCCESS" = false ]; then
        echo "   • Sequential operations failing"
    fi
    if [ "$RAPID_SUCCESS" = false ]; then
        echo "   • Rapid fire operations failing"
    fi
    if [ "$RESPONSE_TYPES_SUCCESS" = false ]; then
        echo "   • Response type handling issues"
    fi
    if [ "$MIXED_SUCCESS" = false ]; then
        echo "   • Mixed operations failing"
    fi
    echo ""
    echo "📋 IMPLICATIONS:"
    echo "   • Response handling bug exists in baseline"
    echo "   • TTL modifications not the root cause"
    echo "   • Need to fix baseline response handling first"
fi

echo ""
echo "$(date): Baseline response handling test complete!"
echo ""

echo "Server log (last 20 lines):"
tail -20 baseline_original.log

echo ""
if [ "$BASELINE_PERFECT" = true ]; then
    echo "🎉 BASELINE IS PERFECT - BUG IS IN MY MODIFICATIONS! 🎉"
else
    echo "🔧 BASELINE HAS RESPONSE HANDLING ISSUES"
fi












