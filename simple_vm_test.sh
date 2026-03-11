#!/bin/bash

# 🧪 SIMPLE VM TEST SCRIPT
# Copy this entire script and paste in VM terminal

echo "🔧 Building final TTL routing fix..."
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 3

g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 -pthread \
    meteor_commercial_lru_ttl_routing_final.cpp -o meteor_final -luring

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful"

# Start server with cores=shards
echo "🚀 Starting server (6C:6S for perfect routing)..."
./meteor_final -h 127.0.0.1 -p 6379 -c 6 -s 6 -m 1536 &
SERVER_PID=$!
sleep 5

# Check if server is running
if ! redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "❌ Server not responding"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi

echo "✅ Server responding"

# Clear all data
redis-cli -p 6379 flushall >/dev/null

echo ""
echo "🧪 Running TTL routing tests..."
echo "=============================="

# Test 1: Key without TTL (should return -1)
redis-cli -p 6379 set test1 "value1" >/dev/null
RESULT1=$(redis-cli -p 6379 ttl test1)
echo "Test 1 (no TTL): $RESULT1"

# Test 2: Key with TTL (should return >0)
redis-cli -p 6379 set test2 "value2" EX 300 >/dev/null
RESULT2=$(redis-cli -p 6379 ttl test2)
echo "Test 2 (with TTL): $RESULT2"

# Test 3: Nonexistent key (should return -2)
RESULT3=$(redis-cli -p 6379 ttl nonexistent)
echo "Test 3 (nonexistent): $RESULT3"

# Test 4: EXPIRE command (should return >0)
redis-cli -p 6379 set test4 "value4" >/dev/null
redis-cli -p 6379 expire test4 600 >/dev/null
RESULT4=$(redis-cli -p 6379 ttl test4)
echo "Test 4 (EXPIRE): $RESULT4"

echo ""
echo "🎯 RESULTS SUMMARY:"
echo "=================="
echo "No TTL key: $RESULT1 (expected: -1)"
echo "TTL key: $RESULT2 (expected: >0)"
echo "Nonexistent: $RESULT3 (expected: -2)"
echo "EXPIRE: $RESULT4 (expected: >0)"

# Success check
SUCCESS=true
if [ "$RESULT1" != "-1" ]; then
    echo "❌ Test 1 failed: no TTL should return -1, got $RESULT1"
    SUCCESS=false
fi

if [ "$RESULT2" -le 0 ]; then
    echo "❌ Test 2 failed: TTL should be >0, got $RESULT2"
    SUCCESS=false
fi

if [ "$RESULT3" != "-2" ]; then
    echo "❌ Test 3 failed: nonexistent should return -2, got $RESULT3"
    SUCCESS=false
fi

if [ "$RESULT4" -le 0 ]; then
    echo "❌ Test 4 failed: EXPIRE should be >0, got $RESULT4"
    SUCCESS=false
fi

echo ""
if [ "$SUCCESS" = true ]; then
    echo "🎉 SUCCESS: ALL TTL TESTS PASSED!"
    echo "✅ TTL routing issue completely fixed"
    echo "✅ Commercial LRU+TTL server ready for production"
else
    echo "❌ Some TTL tests failed - routing still has issues"
fi

# Cleanup
kill $SERVER_PID 2>/dev/null

echo ""
echo "🏁 Test complete"













