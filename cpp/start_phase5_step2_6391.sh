#!/bin/bash
echo "🚀 Starting Phase 5 Step 2 on port 6391..."
nohup ./build/meteor_phase5_step2_6391 -h 127.0.0.1 -p 6391 -s 16 -m 256 > /tmp/meteor_phase5_step2_6391.log 2>&1 &
PID=$!
echo "Started with PID: $PID"
sleep 3
if ps -p $PID > /dev/null; then
    echo "✅ Server is running!"
    ss -tuln | grep 6391 && echo "✅ Port 6391 is listening"
else
    echo "❌ Server failed to start"
    tail -10 /tmp/meteor_phase5_step2_6391.log
fi
