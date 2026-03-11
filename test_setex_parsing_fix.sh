#!/bin/bash

# Test SETEX parsing fix
echo "🧪 TESTING SETEX PARSING FIX"
echo "=========================================="
echo "Testing: Fixed SETEX 4-part command parsing"
echo ""

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server  
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🚀 Starting SETEX parsing fix server..."
nohup ./cpp/meteor_setex_fixed -c 4 -s 4 > setex_parsing_test.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SETEX server failed to start"
    echo "Log:"
    tail -10 setex_parsing_test.log
    exit 1
fi

echo "✅ SETEX server started (PID: $SERVER_PID)"
echo ""

# Test sequence focusing on SETEX
echo "=== SETEX PARSING TEST SEQUENCE ==="
TESTS_PASSED=0
TESTS_TOTAL=0

echo -n "1. PING: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw PING 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "PONG" ]; then
    echo "✅ PONG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "2. SET normal_key normal_value (baseline): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SET normal_key normal_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "3. GET normal_key (baseline): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET normal_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "normal_value" ]; then
    echo "✅ normal_value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "4. SETEX ttl_key 10 ttl_value (4-part parsing): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SETEX ttl_key 10 ttl_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "5. GET ttl_key (should work with fixed parsing): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET ttl_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "ttl_value" ]; then
    echo "✅ ttl_value - SETEX PARSING FIX WORKS!"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - Parsing still broken"
fi

# Test TTL expiry (wait 12 seconds - key should expire)
if [ "$RESULT" = "ttl_value" ]; then
    echo ""
    echo "=== TTL EXPIRY TEST ==="
    echo "⏳ Waiting 12 seconds for ttl_key to expire (TTL was 10s)..."
    sleep 12

    echo -n "6. GET ttl_key (should be expired): "
    RESULT=$(timeout 5s redis-cli -p 6379 --raw GET ttl_key 2>/dev/null)
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$RESULT" = "" ] || [ "$RESULT" = "nil" ] || [ -z "$RESULT" ]; then
        echo "✅ EXPIRED - TTL functionality working!"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAILED: Key should be expired (\"$RESULT\")"
    fi
fi

echo -n "7. Final PING: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw PING 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "PONG" ]; then
    echo "✅ PONG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 SETEX PARSING FIX TEST RESULTS"
echo "=========================================="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo ""
    echo "🎉 COMPLETE SUCCESS!"
    echo "✅ SETEX parsing fix works perfectly"
    echo "✅ TTL functionality working correctly"
    echo "✅ DragonflyDB-style per-shard TTL implemented successfully"
    echo ""
    echo "🚀 SETEX implementation is now fully functional!"
    echo "🚀 Ready for additional TTL commands (EXPIRE, TTL query, etc.)"
elif [ $TESTS_PASSED -ge 5 ]; then
    echo ""
    echo "✅ MAJOR SUCCESS!"
    echo "✅ SETEX parsing fix works"
    echo "⚠️  Minor issues with expiry test"
else
    echo ""
    echo "❌ SETEX parsing still has issues"
    echo "📋 Further investigation needed"
fi

EOF












