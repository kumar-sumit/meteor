#!/bin/bash

echo "🚀 PHASE 5 STEP 4A - 16-CORE SIMPLE STARTUP"
echo "=========================================="

# Stop existing servers
pkill -f meteor || true
sleep 3

# Start 16-core server (no SSD)
echo "Starting 16-core server..."
echo "Command: ~/meteor_phase5_mcache -h 0.0.0.0 -p 6391 -c 16 -s 16 -m 32768 -l"

nohup ~/meteor_phase5_mcache -h 0.0.0.0 -p 6391 -c 16 -s 16 -m 32768 -l > ~/phase5_16core.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
sleep 20

# Check status
if ps -p $SERVER_PID > /dev/null && ss -tlnp | grep :6391; then
    echo "✅ 16-core server running on port 6391"
    uptime
    free -h | grep Mem
else
    echo "❌ Server failed"
    tail -15 ~/phase5_16core.log
fi