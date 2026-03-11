#!/bin/bash

echo "🚀 PHASE 5 STEP 4A - 16-CORE + SSD SERVER STARTUP"
echo "================================================="
echo "Target: mcache-ssd-tiering-poc VM"
echo "Configuration: 16 cores, 16 shards, 32GB memory, SSD cache"
echo

# Stop any existing servers
echo "🔧 Stopping existing servers..."
pkill -f meteor || true
sleep 5

# Start 16-core server with SSD cache
echo "🚀 Starting 16-core + SSD Phase 5 server..."
echo "Command: ~/meteor_phase5_mcache -h 0.0.0.0 -p 6391 -c 16 -s 16 -m 32768 -ssd /mnt/localDiskSSD/meteor_cache -l"

nohup ~/meteor_phase5_mcache -h 0.0.0.0 -p 6391 -c 16 -s 16 -m 32768 -ssd /mnt/localDiskSSD/meteor_cache -l > ~/phase5_16core_ssd.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting 30 seconds for initialization..."
sleep 30

# Check server status
echo "🔍 Checking server status..."
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server process running"
    
    if ss -tlnp | grep :6391; then
        echo "✅ Server listening on port 6391"
        echo
        echo "📊 System Status:"
        echo "================"
        uptime
        echo
        free -h | grep Mem
        echo
        echo "🎉 16-CORE + SSD server ready for benchmarking!"
        echo "Address: 172.23.72.71:6391"
        
    else
        echo "❌ Server not listening on port 6391"
        echo "Server log:"
        tail -20 ~/phase5_16core_ssd.log
    fi
else
    echo "❌ Server process died"
    echo "Server log:"
    tail -20 ~/phase5_16core_ssd.log
fi