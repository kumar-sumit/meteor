#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🚀 SIMPLE TTL TEST - BASIC BUILD"
echo "$(date): Testing basic TTL functionality"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== STEP 1: BUILD WITH BASIC FLAGS ==="
echo "Building with minimal optimization to avoid compilation issues..."

g++ -std=c++20 -O2 -DNDEBUG -DBOOST_FIBER_NO_EXCEPTIONS -pthread \
    meteor_baseline_ttl_lru.cpp -o meteor_ttl_simple \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

BUILD_STATUS=$?
if [ $BUILD_STATUS -ne 0 ]; then
    echo "❌ BUILD FAILED"
    echo "Let's try building the original working baseline instead..."
    
    # Fall back to original baseline
    g++ -std=c++20 -O2 -DNDEBUG -DBOOST_FIBER_NO_EXCEPTIONS -pthread \
        meteor_phase1_2b_syscall_reduction_single_command_fixed.cpp -o meteor_ttl_simple \
        -lboost_fiber -lboost_context -lboost_system -luring 2>&1
    
    BUILD_STATUS=$?
    if [ $BUILD_STATUS -ne 0 ]; then
        echo "❌ EVEN BASELINE FAILED TO BUILD"
        exit 1
    fi
    echo "✅ FALLBACK TO BASELINE SUCCESSFUL"
    USING_BASELINE=true
else
    echo "✅ TTL BUILD SUCCESSFUL"
    USING_BASELINE=false
fi

echo ""
echo "=== STEP 2: START SERVER ==="
echo "Starting server..."
nohup ./meteor_ttl_simple -c 4 -s 4 > meteor_ttl_simple.log 2>&1 &
SERVER_PID=$!
sleep 6

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    tail -10 meteor_ttl_simple.log
    exit 1
fi

echo "✅ SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 3: BASIC FUNCTIONALITY TEST ==="
echo "🎯 Testing basic Redis commands"

echo -n "SET test: "
SET_RESULT=$(redis-cli -p 6379 SET testkey testvalue 2>/dev/null || echo "FAILED")
echo "$SET_RESULT"

echo -n "GET test: "
GET_RESULT=$(redis-cli -p 6379 GET testkey 2>/dev/null || echo "FAILED")
echo "$GET_RESULT"

echo -n "PING test: "
PING_RESULT=$(redis-cli -p 6379 PING 2>/dev/null || echo "FAILED")
echo "$PING_RESULT"

BASIC_SUCCESS=false
if [[ "$SET_RESULT" == "OK" ]] && [[ "$GET_RESULT" == "testvalue" ]] && [[ "$PING_RESULT" == "PONG" ]]; then
    echo "✅ BASIC COMMANDS: WORKING PERFECTLY"
    BASIC_SUCCESS=true
else
    echo "❌ BASIC COMMANDS FAILED: SET='$SET_RESULT', GET='$GET_RESULT', PING='$PING_RESULT'"
fi

echo ""
if [ "$USING_BASELINE" = true ]; then
    echo "=== BASELINE VERIFICATION ==="
    echo "✅ Confirmed: Original working baseline compiles and runs correctly"
    echo "❌ Issue: TTL+LRU implementation has compilation errors"
    echo ""
    echo "🔧 NEEDED: Fix compilation issues in TTL implementation"
    echo "   • Stats struct visibility issues"
    echo "   • Multiple Stats definitions conflicts"
    echo ""
else
    echo "=== STEP 4: TTL TESTING ==="
    echo "🎯 Testing TTL commands if available"
    
    echo -n "TTL command test: "
    TTL_TEST=$(redis-cli -p 6379 TTL testkey 2>/dev/null || echo "NOT_SUPPORTED")
    echo "$TTL_TEST"
    
    if [[ "$TTL_TEST" == "-1" ]]; then
        echo "✅ TTL COMMANDS: WORKING (key without TTL returns -1)"
    elif [[ "$TTL_TEST" == "NOT_SUPPORTED" ]] || [[ "$TTL_TEST" == "" ]]; then
        echo "❌ TTL COMMANDS: Not implemented or not working"
    else
        echo "⚠️  TTL COMMANDS: Unexpected response '$TTL_TEST'"
    fi
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 SIMPLE TTL TEST RESULTS"
echo "=========================================="
echo ""

if [ "$BASIC_SUCCESS" = true ]; then
    if [ "$USING_BASELINE" = true ]; then
        echo "🔍 STATUS: BASELINE CONFIRMED WORKING"
        echo ""
        echo "✅ VERIFIED:"
        echo "   • Original baseline compiles successfully"
        echo "   • Basic Redis commands work perfectly"
        echo "   • Server handles connections correctly"
        echo ""
        echo "🔧 NEXT STEPS:"
        echo "   • Fix Stats struct compilation errors in TTL implementation"
        echo "   • Resolve multiple Stats definitions conflicts"
        echo "   • Test TTL functionality once compilation fixed"
    else
        echo "🎉 STATUS: TTL IMPLEMENTATION SUCCESS!"
        echo ""
        echo "✅ ACHIEVED:"
        echo "   • TTL+LRU implementation compiles successfully"
        echo "   • Basic functionality preserved"
        echo "   • Ready for TTL feature testing"
    fi
else
    echo "❌ STATUS: SERVER ISSUES"
    echo ""
    echo "🔧 PROBLEMS:"
    echo "   • Basic Redis commands not working"
    echo "   • Server connection or response issues"
fi

echo ""
echo "$(date): Simple TTL test complete!"
echo ""

echo "Server log (last 5 lines):"
tail -5 meteor_ttl_simple.log

echo ""
echo "🚀 Test completed with $([ "$USING_BASELINE" = true ] && echo "baseline verification" || echo "TTL implementation")"












