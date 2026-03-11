#!/bin/bash

cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor || true

echo "🔧 ROUTING DEBUG TEST"
echo "==================="

# Build
echo "Building routing debug version..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
    meteor_routing_debug.cpp -o meteor_routing_test \
    -luring -lboost_fiber -lboost_context -lboost_system -pthread

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful!"

# Start server
echo ""
echo "🚀 Starting server with routing debug (6C:3S)..."
./meteor_routing_test -h 127.0.0.1 -p 6379 -c 6 -s 3 -m 1536 > debug.log 2>&1 &
SERVER_PID=$!

echo "Server started, waiting for initialization..."
sleep 8

# Test basic connectivity
PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)
if [ "$PING_RESULT" = "PONG" ]; then
    echo "✅ Server responding"
    
    echo ""
    echo "🧪 ROUTING DEBUG TEST:"
    echo "====================="
    echo "Commands will show routing decisions and coordinator status"
    
    # Test commands with debug output
    echo ""
    echo "Test 1: SET command"
    redis-cli -p 6379 set debug_key_1 debug_value_1
    
    echo ""
    echo "Test 2: GET command"
    redis-cli -p 6379 get debug_key_1
    
    echo ""
    echo "Test 3: Different key"
    redis-cli -p 6379 set debug_key_2 debug_value_2
    redis-cli -p 6379 get debug_key_2
    
    echo ""
    echo "Test 4: Keys that should force different core routing"
    for key in test_a test_b test_c test_d test_e test_f; do
        echo "Testing key: $key"
        redis-cli -p 6379 set $key value_$key
        redis-cli -p 6379 get $key
    done
    
else
    echo "❌ Server not responding: '$PING_RESULT'"
fi

# Show debug logs
echo ""
echo "🔍 DEBUG LOG ANALYSIS:"
echo "====================="

echo ""
echo "Cross-shard coordinator initialization:"
grep "initialized cross-shard coordinator" debug.log || echo "No coordinator init messages found"

echo ""
echo "Cross-shard processor startup:"
grep "started cross-shard processor" debug.log || echo "No processor startup messages found"

echo ""
echo "Routing decisions:"
grep -E "Core.*processing|LOCAL PATH|CROSS-SHARD ROUTING|Coordinator status" debug.log | head -20 || echo "No routing messages found"

echo ""
echo "Cross-shard execution:"
grep -E "Cross-shard executor|Cross-shard.*response" debug.log | head -10 || echo "No cross-shard execution found"

# Cleanup
kill $SERVER_PID 2>/dev/null

echo ""
echo "🏁 Routing debug test completed"
echo ""
echo "Expected debug output:"
echo "- Coordinator initialization messages"
echo "- Processor startup for shards 0, 1, 2"
echo "- Routing decisions showing local vs cross-shard"
echo "- Coordinator status: AVAILABLE"
echo "- Cross-shard execution messages"













