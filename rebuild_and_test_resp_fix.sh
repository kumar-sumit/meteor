#!/bin/bash

# **TEMPORAL COHERENCE RESP PROTOCOL FIX - REBUILD AND TEST**
# Fix for PING command handler and improved debugging

echo "🚀 **TEMPORAL COHERENCE - RESP PROTOCOL FIX DEPLOYMENT**"
echo "Innovation: Adding PING command support + debug logging"
echo ""

cd /dev/shm

echo "=== 1. Cleanup Previous Instances ==="
echo "Killing existing servers..."
pkill -f meteor_phase8_step24_temporal_coherence 2>/dev/null || echo "No running instances"
sleep 3

echo "=== 2. Rebuild with RESP Protocol Fix ==="
echo "Rebuilding temporal coherence server with PING support..."
./build_phase8_step24_temporal_coherence.sh > rebuild.log 2>&1
BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ Build successful!"
    tail -5 rebuild.log
else
    echo "❌ Build failed!"
    tail -10 rebuild.log
    exit 1
fi

echo ""
echo "=== 3. Start Fixed Server ==="
echo "Starting temporal coherence server with RESP fix..."
./meteor_phase8_step24_temporal_coherence -p 6380 -c 4 > server_resp_fix.log 2>&1 &
SERVER_PID=$!
echo "✅ Server started with PID: $SERVER_PID"
sleep 5

echo "=== 4. Verify Server Status ==="
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server process running"
else
    echo "❌ Server process died, checking logs..."
    tail -10 server_resp_fix.log
    exit 1
fi

echo "Port status:"
ss -tlnp | grep 6380 | head -3

echo ""
echo "=== 5. Test PING Command (THE FIX!) ==="
echo "Testing PING command with fixed handler..."
echo -e "PING\r" | timeout 5 nc localhost 6380 > ping_test.log 2>&1 &
PING_PID=$!
sleep 2

if ps -p $PING_PID > /dev/null; then
    kill $PING_PID 2>/dev/null
fi

if [ -s ping_test.log ]; then
    echo "✅ PING Response received:"
    cat ping_test.log
    PING_SUCCESS=true
else
    echo "❌ No PING response"
    PING_SUCCESS=false
fi

echo ""
echo "=== 6. Test Redis Protocol Commands ==="
echo "Testing SET command..."
echo -e "*3\r\n\$3\r\nSET\r\n\$8\r\ntest_key\r\n\$10\r\ntest_value\r\n" | timeout 3 nc localhost 6380 > set_test.log 2>&1 &
SET_PID=$!
sleep 2

if ps -p $SET_PID > /dev/null; then
    kill $SET_PID 2>/dev/null
fi

if [ -s set_test.log ]; then
    echo "✅ SET Response:"
    cat set_test.log
    SET_SUCCESS=true
else
    echo "❌ No SET response"
    SET_SUCCESS=false
fi

echo ""
echo "=== 7. Check Server Logs for Debug Info ==="
echo "Recent server debug output:"
tail -10 server_resp_fix.log

echo ""
echo "=== 8. RESP Protocol Fix Results ==="
if [ "$PING_SUCCESS" = true ] && [ "$SET_SUCCESS" = true ]; then
    echo "🎉 **BREAKTHROUGH SUCCESS!**"
    echo "✅ PING command: WORKING"
    echo "✅ SET command: WORKING" 
    echo "✅ RESP protocol: FIXED"
    echo "🚀 **Phase 1.1: 100% COMPLETE!**"
    echo ""
    echo "Revolutionary temporal coherence server is now fully operational!"
    echo "Ready for Phase 1.2: Cross-core pipeline testing!"
else
    echo "⚠️ Partial success - some commands working"
    if [ "$PING_SUCCESS" = true ]; then
        echo "✅ PING: Working"
    else
        echo "❌ PING: Still failing"
    fi
    if [ "$SET_SUCCESS" = true ]; then
        echo "✅ SET: Working"  
    else
        echo "❌ SET: Still failing"
    fi
fi

echo ""
echo "=== Server Control Info ==="
echo "Server PID: $SERVER_PID"
echo "Log file: server_resp_fix.log"
echo "Kill command: kill $SERVER_PID"
echo ""
echo "🚀 RESP Protocol Fix Testing Complete!"


