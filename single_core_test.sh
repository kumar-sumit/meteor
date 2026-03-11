#!/bin/bash

echo "🔍 SINGLE CORE DEBUG TEST"
echo "========================================"

cd /home/sumit.kumar/meteor-persistent-test

# Kill any existing servers
killall meteor_redis_persistent 2>/dev/null || true
sleep 2

# Setup test directory
rm -rf test_single_core
mkdir -p test_single_core/{snapshots,aof}

# Start server with SINGLE CORE
echo "🚀 Starting server with 1 core, 1 shard..."
./meteor_redis_persistent -p 6390 -c 1 -s 1 -P 1 \
    -R ./test_single_core/snapshots \
    -A ./test_single_core/aof \
    -I 20 -O 5000 -F 1 > test_single_core/server.log 2>&1 &

SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 3

# Test if server is running
redis-cli -p 6390 PING > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Server failed to start"
    cat test_single_core/server.log
    exit 1
fi

echo "✅ Server started successfully"
echo ""

# Write 20 test keys
echo "📝 Writing 20 test keys..."
for i in {1..20}; do
    redis-cli -p 6390 SET "testkey_$i" "testvalue_$i" > /dev/null
done
echo "✅ Wrote 20 keys"
echo ""

# Read back all 20 keys
echo "🔍 Reading back all 20 keys..."
MISSING=0
for i in {1..20}; do
    VALUE=$(redis-cli -p 6390 GET "testkey_$i")
    if [ "$VALUE" == "testvalue_$i" ]; then
        echo "  ✅ testkey_$i = testvalue_$i"
    else
        echo "  ❌ testkey_$i MISSING (got: '$VALUE')"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
echo "========================================"
if [ $MISSING -eq 0 ]; then
    echo "✅ SUCCESS: All 20 keys stored and retrieved!"
else
    echo "❌ FAILURE: $MISSING keys missing"
fi
echo "========================================"
echo ""

# Wait for snapshot
echo "⏳ Waiting 25 seconds for RDB snapshot..."
sleep 25

# Check snapshot files
echo "📂 Checking snapshot files:"
ls -lh test_single_core/snapshots/*.rdb 2>/dev/null | tail -3
echo ""
echo "📂 Checking AOF file:"
ls -lh test_single_core/aof/meteor.aof
echo ""

# Check server logs for snapshot
echo "📋 Server logs (last 30 lines):"
tail -30 test_single_core/server.log | grep -E "(snapshot|Collected|keys)"
echo ""

# Test crash recovery
echo "========================================"
echo "🔥 CRASH RECOVERY TEST"
echo "========================================"
echo "Killing server with kill -9..."
kill -9 $SERVER_PID
sleep 2

echo "Restarting server..."
./meteor_redis_persistent -p 6390 -c 1 -s 1 -P 1 \
    -R ./test_single_core/snapshots \
    -A ./test_single_core/aof \
    -I 20 -O 5000 -F 1 > test_single_core/recovery.log 2>&1 &

NEW_PID=$!
sleep 5

# Check recovery
echo "📋 Recovery logs:"
grep -E "(Loaded|Replayed|Total recovered|Loading)" test_single_core/recovery.log

echo ""
echo "🔍 Verifying recovered data..."
RECOVERED=0
for i in {1..20}; do
    VALUE=$(redis-cli -p 6390 GET "testkey_$i")
    if [ "$VALUE" == "testvalue_$i" ]; then
        RECOVERED=$((RECOVERED + 1))
    fi
done

echo "✅ Recovered $RECOVERED out of 20 keys"

# Cleanup
kill $NEW_PID 2>/dev/null

echo ""
echo "========================================"
echo "TEST COMPLETE"
echo "========================================"



