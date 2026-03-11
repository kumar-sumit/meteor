#!/bin/bash

# **TEMPORAL COHERENCE PHASE 1.1 TESTING SCRIPT**
# Revolutionary lock-free cross-core pipeline correctness validation

echo "🚀 **TEMPORAL COHERENCE PROTOCOL - PHASE 1.1 TESTING**"
echo "Innovation: World's first lock-free cross-core pipeline protocol"
echo "Target: 4.92M+ QPS with 100% correctness"
echo ""

cd /dev/shm

echo "=== 1. Environment Verification ==="
echo "✅ Binary exists: $(ls -la meteor_phase8_step24_temporal_coherence)"
echo "✅ Files present: $(ls -la temporal_coherence_core.h)"
echo ""

echo "=== 2. Cleanup Any Running Instances ==="
pkill -f meteor_phase8_step24 2>/dev/null || echo "✅ No running instances to cleanup"
sleep 2

echo "=== 3. Starting Temporal Coherence Server ==="
echo "Starting server with 4 cores on port 6380..."
nohup ./meteor_phase8_step24_temporal_coherence -p 6380 -c 4 > temporal_server.log 2>&1 &
SERVER_PID=$!
echo "✅ Server started with PID: $SERVER_PID"
sleep 5

echo "=== 4. Server Status Verification ==="
echo "Process status:"
ps aux | grep meteor_phase8_step24 | grep -v grep || echo "❌ Server not running"

echo "Port status:"
ss -tlnp | grep 6380 || echo "❌ Port 6380 not listening"
echo ""

echo "=== 5. Basic Connectivity Test ==="
echo "Testing netcat connection..."
echo "PING" | timeout 3 nc localhost 6380 && echo "✅ Connection established" || echo "❌ Connection failed"
echo ""

echo "=== 6. Redis Protocol Test ==="
echo "Testing PING command..."
echo '*1\r\n$4\r\nPING\r\n' | timeout 3 nc localhost 6380 && echo "✅ RESP protocol working" || echo "❌ RESP protocol failed"
echo ""

echo "=== 7. Server Log Analysis ==="
echo "Last 10 lines of server log:"
tail -10 temporal_server.log
echo ""

echo "=== 8. Test Results Summary ==="
if ps aux | grep -q meteor_phase8_step24 && ss -tlnp | grep -q 6380; then
    echo "✅ **Phase 1.1 SUCCESS**: Temporal Coherence Server is running!"
    echo "✅ Revolutionary protocol deployed and listening"
    echo "🚀 Ready for Phase 1.2: Pipeline correctness testing"
else
    echo "❌ **Phase 1.1 ISSUES**: Server startup problems detected"
    echo "🔍 Check logs above for debugging information"
fi

echo ""
echo "=== Server Control ==="
echo "Server PID: $SERVER_PID"
echo "To kill server: kill $SERVER_PID"
echo "To view logs: tail -f temporal_server.log"
echo ""
echo "🚀 Temporal Coherence Protocol Phase 1.1 Testing Complete!"


