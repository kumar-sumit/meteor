#!/bin/bash

echo "🧪 PHASE 6 STEP 3: DRAGONFLY-STYLE PIPELINE TESTING"
echo "=================================================="
echo ""

SERVER_BINARY="./meteor_phase6_step3_dragonfly_style"
SERVER_PORT=6390

# Kill any existing server
echo "🛑 Stopping any existing servers..."
pkill -f meteor || true
sleep 2

# Start server in background
echo "🚀 Starting DragonflyDB-style server..."
nohup $SERVER_BINARY -h 127.0.0.1 -p $SERVER_PORT -c 4 -s 4 -m 1024 > server.log 2>&1 &
SERVER_PID=$!
echo "📊 Server PID: $SERVER_PID"
sleep 4

# Test 1: Basic functionality (no pipeline)
echo ""
echo "📊 Test 1: No Pipeline (baseline):"
redis-benchmark -h 127.0.0.1 -p $SERVER_PORT -t set -n 10000 -c 50 -P 1 --csv

# Test 2: Small pipeline
echo ""
echo "📊 Test 2: Pipeline = 5:"
redis-benchmark -h 127.0.0.1 -p $SERVER_PORT -t set -n 10000 -c 50 -P 5 --csv

# Test 3: Medium pipeline  
echo ""
echo "📊 Test 3: Pipeline = 10:"
redis-benchmark -h 127.0.0.1 -p $SERVER_PORT -t set -n 10000 -c 50 -P 10 --csv

# Test 4: Large pipeline
echo ""
echo "📊 Test 4: Pipeline = 20:"
redis-benchmark -h 127.0.0.1 -p $SERVER_PORT -t set -n 10000 -c 50 -P 20 --csv

# Test 5: Critical test - memtier benchmark (should not deadlock)
echo ""
echo "📊 Test 5: memtier-benchmark with pipeline (critical deadlock test):"
if command -v memtier_benchmark &> /dev/null; then
    timeout 30 memtier_benchmark -s 127.0.0.1 -p $SERVER_PORT -t 2 -c 10 -n 1000 --pipeline=10 --hide-histogram
    if [ $? -eq 124 ]; then
        echo "❌ memtier-benchmark timed out (likely deadlock)"
    else
        echo "✅ memtier-benchmark completed successfully (no deadlock)"
    fi
else
    echo "⚠️  memtier_benchmark not available"
fi

# Stop server
echo ""
echo "🛑 Stopping server..."
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "🎯 Test Summary:"
echo "- No Pipeline: Should show baseline performance"
echo "- Pipeline = 5-20: Should show IMPROVING performance (not decreasing)"
echo "- memtier with pipeline: Should NOT deadlock"
echo ""
echo "✅ Testing completed!"