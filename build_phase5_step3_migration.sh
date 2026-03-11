#!/bin/bash
# Build script for Phase 5 Step 3 Connection Migration

echo "🔧 Building Phase 5 Step 3 (Connection Migration)..."
cd ~/meteor

# Kill any existing servers
pkill -f meteor_phase5 2>/dev/null || true
sleep 2

# Build the connection migration version
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -o meteor_phase5_step3_migration sharded_server_phase5_step3_connection_migration.cpp -pthread

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📊 Starting server for testing..."
    
    # Start server in background
    nohup ./meteor_phase5_step3_migration -c 16 -s 16 -p 6379 > server_migration_step3.log 2>&1 &
    sleep 3
    
    echo "🚀 Running benchmark to test connection migration..."
    memtier_benchmark -s localhost -p 6379 -c 5 -t 2 --ratio=1:1 --test-time=30 -d 512 --hide-histogram
    
    echo "📋 Server log tail (showing migration activity):"
    tail -30 server_migration_step3.log
else
    echo "❌ Build failed!"
    exit 1
fi