#!/bin/bash
# Build script for Phase 5 Step 1 Enhanced Dragonfly-style server

echo "🔧 Building Phase 5 Step 1 Enhanced (Dragonfly-style)..."
cd ~/meteor

# Kill any existing servers
pkill -f meteor_phase5 2>/dev/null || true
sleep 2

# Build the enhanced version
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -o meteor_phase5_step1_enhanced sharded_server_phase5_step1_enhanced_dragonfly.cpp -pthread

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📊 Starting server for testing..."
    
    # Start server in background
    nohup ./meteor_phase5_step1_enhanced -c 16 -s 16 -p 6379 > server_enhanced_step1.log 2>&1 &
    sleep 3
    
    echo "🚀 Running quick benchmark..."
    memtier_benchmark -s localhost -p 6379 -c 5 -t 2 --ratio=1:1 --test-time=30 -d 512 --hide-histogram
    
    echo "📋 Server log tail:"
    tail -20 server_enhanced_step1.log
else
    echo "❌ Build failed!"
    exit 1
fi