#!/bin/bash

echo "🔍 MULTI-CORE DEBUG TEST (4 cores)"
echo "========================================"

cd /home/sumit.kumar/meteor-persistent-test

# Kill any existing servers
killall meteor_redis_persistent 2>/dev/null || true
sleep 2

# Setup test directory
rm -rf test_multi_core
mkdir -p test_multi_core/{snapshots,aof}

# Start server with 4 CORES and LOGGING ENABLED
echo "🚀 Starting server with 4 cores, 4 shards, logging enabled..."
./meteor_redis_persistent -p 6390 -c 4 -s 4 -P 1 \
    -R ./test_multi_core/snapshots \
    -A ./test_multi_core/aof \
    -I 20 -O 5000 -F 1 -l > test_multi_core/server.log 2>&1 &

SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 3

# Test if server is running
redis-cli -p 6390 PING > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Server failed to start"
    cat test_multi_core/server.log
    exit 1
fi

echo "✅ Server started successfully"
echo ""

# Write 20 test keys (same as single-core test)
echo "📝 Writing 20 test keys..."
for i in {1..20}; do
    redis-cli -p 6390 SET "testkey_$i" "testvalue_$i" > /dev/null
done
echo "✅ Wrote 20 keys"
echo ""

# Read back all 20 keys
echo "🔍 Reading back all 20 keys..."
MISSING=0
FOUND=0
for i in {1..20}; do
    VALUE=$(redis-cli -p 6390 GET "testkey_$i")
    if [ "$VALUE" == "testvalue_$i" ]; then
        echo "  ✅ testkey_$i = testvalue_$i"
        FOUND=$((FOUND + 1))
    else
        echo "  ❌ testkey_$i MISSING (got: '$VALUE')"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
echo "========================================"
echo "📊 Results: $FOUND found, $MISSING missing"
if [ $MISSING -eq 0 ]; then
    echo "✅ SUCCESS: All 20 keys stored and retrieved!"
else
    echo "⚠️  PARTIAL SUCCESS: $(echo "scale=1; $FOUND*100/20" | bc)% success rate"
fi
echo "========================================"
echo ""

# Wait for snapshot
echo "⏳ Waiting 25 seconds for RDB snapshot..."
sleep 25

# Check snapshot files
echo "📂 Checking snapshot files:"
ls -lh test_multi_core/snapshots/*.rdb 2>/dev/null | tail -3
echo ""

# Check server logs for snapshot details
echo "📋 Snapshot collection logs:"
grep -A10 "Collecting data from" test_multi_core/server.log | tail -20
echo ""

# Cleanup
kill $SERVER_PID 2>/dev/null

echo "========================================"
echo "TEST COMPLETE"
echo "Full logs in: test_multi_core/server.log"
echo "========================================"



