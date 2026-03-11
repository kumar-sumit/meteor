#!/bin/bash
echo "🚀 Starting Phase 5 Step 2 on port 6391 (light config)..."
nohup ./build/meteor_phase5_step2_6391 -h 127.0.0.1 -p 6391 -s 8 -m 128 > /tmp/meteor_phase5_step2_6391_light.log 2>&1 &
PID=$!
echo "Started with PID: $PID"
sleep 5
if ps -p $PID > /dev/null; then
    echo "✅ Server is running!"
    ss -tuln | grep 6391 && echo "✅ Port 6391 is listening"
    echo "🔍 Testing connectivity..."
    redis-cli -h 127.0.0.1 -p 6391 ping || echo "Connection test failed"
else
    echo "❌ Server failed to start"
    tail -15 /tmp/meteor_phase5_step2_6391_light.log
fi
