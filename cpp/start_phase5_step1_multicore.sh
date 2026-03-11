#!/bin/bash
echo '🚀 Starting Phase 5 Step 1: Multi-Core Event Loop Server'
echo 'Port: 6391, Shards: 22, Memory: 2048MB per shard'
echo 'Features: Multi-Core Event Loops + All Phase 4 Step 3 Features'

# Kill any existing server on port 6391
PIDS=$(ps aux | grep 'meteor_phase5_step1_multicore.*-p 6391' | grep -v grep | awk '{print $2}')
if [ -n "$PIDS" ]; then
    echo "Killing existing processes: $PIDS"
    kill -9 $PIDS
    sleep 2
fi

echo "Starting Multi-Core Event Server..."
nohup ./build/meteor_phase5_step1_multicore_debug -h 127.0.0.1 -p 6391 -s 22 -m 2048 > /tmp/meteor_phase5_step1_multicore.log 2>&1 &
PID=$!
echo "Started with PID: $PID"

sleep 5

if ps -p $PID > /dev/null; then
    echo "✅ Multi-Core Server is running!"
    ss -tuln | grep 6391 && echo "✅ Port 6391 is listening"
    echo "🔍 Testing connectivity..."
    redis-cli -h 127.0.0.1 -p 6391 ping || echo "Connection test failed"
    echo "📊 CPU Cores detected: $(nproc)"
    echo "📊 Server should utilize all $(nproc) cores!"
else
    echo "❌ Server failed to start"
    tail -15 /tmp/meteor_phase5_step1_multicore.log
fi 