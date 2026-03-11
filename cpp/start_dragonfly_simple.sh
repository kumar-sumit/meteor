#!/bin/bash

echo "🐲 STARTING DRAGONFLY ON SSD-TIERING VM"
echo "======================================"
echo "Simple startup script for remote benchmarking"
echo

# Kill any existing processes
echo "🛑 Stopping existing servers..."
pkill -f dragonfly || true
pkill -f meteor || true
sleep 3

# Start DragonflyDB with optimal settings
echo "🚀 Starting DragonflyDB..."
echo "Configuration: 16 threads, port 6380, bind to all interfaces"
echo "Command: dragonfly --port=6380 --bind=0.0.0.0 --proactor_threads=16"

nohup dragonfly --port=6380 --bind=0.0.0.0 --proactor_threads=16 --logtostderr > ~/dragonfly_simple.log 2>&1 &
DRAGONFLY_PID=$!

echo "DragonflyDB started with PID: $DRAGONFLY_PID"
echo "Waiting 15 seconds for startup..."
sleep 15

# Check if running
if ps -p $DRAGONFLY_PID > /dev/null; then
    echo "✅ DragonflyDB process running"
    if ss -tlnp | grep :6380; then
        echo "✅ DragonflyDB listening on port 6380"
        echo "🌐 Ready for network benchmarking on 172.23.72.71:6380"
        echo
        echo "📊 System status:"
        uptime
        free -h | grep Mem
    else
        echo "❌ DragonflyDB not listening on port 6380"
        echo "Log:"
        tail -10 ~/dragonfly_simple.log
    fi
else
    echo "❌ DragonflyDB process died"
    echo "Log:"
    tail -10 ~/dragonfly_simple.log
fi