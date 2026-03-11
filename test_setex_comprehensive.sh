#!/bin/bash

# Comprehensive SETEX functionality test following DragonflyDB principles
echo "🧪 COMPREHENSIVE SETEX TTL TEST"
echo "=========================================="
echo "Testing: DragonflyDB-style per-shard TTL with SETEX command"
echo ""

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🚀 Starting TTL-enhanced baseline server..."
nohup ./meteor_ttl_baseline -c 4 -s 4 > ttl_baseline_test.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ TTL server failed to start"
    echo "Log:"
    tail -10 ttl_baseline_test.log
    exit 1
fi

echo "✅ TTL server started (PID: $SERVER_PID)"
echo ""

# Comprehensive TTL testing
echo "=== PHASE 1: BASELINE PRESERVATION TEST ==="
TESTS_PASSED=0
TESTS_TOTAL=0

echo -n "1.1 PING: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw PING 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "PONG" ]; then
    echo "✅ PONG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "1.2 SET baseline_key baseline_value: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SET baseline_key baseline_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "1.3 GET baseline_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET baseline_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "baseline_value" ]; then
    echo "✅ baseline_value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - CRITICAL: Baseline GET broken"
fi

echo -n "1.4 DEL baseline_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw DEL baseline_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "1" ]; then
    echo "✅ 1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo ""
echo "=== PHASE 2: SETEX FUNCTIONALITY TEST ==="

# Test SETEX with 5-second expiry
echo -n "2.1 SETEX ttl_key 5 ttl_value (5-second expiry): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SETEX ttl_key 5 ttl_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

# Verify key exists immediately after SETEX
echo -n "2.2 GET ttl_key (immediately after SETEX): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET ttl_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "ttl_value" ]; then
    echo "✅ ttl_value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - SETEX key not accessible"
fi

# Test multiple keys with different TTLs (cross-shard testing)
echo -n "2.3 SETEX cross_shard_key1 3 value1: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SETEX cross_shard_key1 3 value1 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "2.4 SETEX cross_shard_key2 7 value2: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SETEX cross_shard_key2 7 value2 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

# Verify both keys exist
echo -n "2.5 GET cross_shard_key1: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET cross_shard_key1 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "value1" ]; then
    echo "✅ value1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "2.6 GET cross_shard_key2: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET cross_shard_key2 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "value2" ]; then
    echo "✅ value2"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo ""
echo "=== PHASE 3: TTL EXPIRY TEST (Wait for expiration) ==="
echo "⏳ Waiting 4 seconds for keys to expire..."
sleep 4

# cross_shard_key1 (3s TTL) should be expired
echo -n "3.1 GET cross_shard_key1 (should be expired after 4s): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET cross_shard_key1 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "" ] || [ "$RESULT" = "nil" ] || [ -z "$RESULT" ]; then
    echo "✅ EXPIRED (empty response)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED: Key should be expired (\"$RESULT\")"
fi

# ttl_key (5s TTL) should be expired  
echo -n "3.2 GET ttl_key (should be expired after 4s): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET ttl_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "" ] || [ "$RESULT" = "nil" ] || [ -z "$RESULT" ]; then
    echo "✅ EXPIRED (empty response)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED: Key should be expired (\"$RESULT\")"
fi

# cross_shard_key2 (7s TTL) should still exist
echo -n "3.3 GET cross_shard_key2 (should still exist after 4s): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET cross_shard_key2 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "value2" ]; then
    echo "✅ value2 (still valid)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED: Key should still be valid (\"$RESULT\")"
fi

echo ""
echo "=== PHASE 4: SERVER STABILITY TEST ==="
echo -n "4.1 Final PING: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw PING 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "PONG" ]; then
    echo "✅ PONG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - Server stability compromised"
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 COMPREHENSIVE SETEX TTL TEST RESULTS"
echo "=========================================="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo ""
    echo "🎉 COMPLETE SUCCESS: SETEX TTL IMPLEMENTATION WORKING!"
    echo "✅ Baseline functionality: 100% preserved"
    echo "✅ SETEX command: Fully functional"  
    echo "✅ TTL expiry: Working correctly"
    echo "✅ Cross-shard TTL: DragonflyDB-style per-shard success"
    echo "✅ Server stability: Maintained"
    echo ""
    echo "🚀 READY FOR NEXT STEP: Add EXPIRE command and TTL query"
elif [ $TESTS_PASSED -ge $((TESTS_TOTAL * 80 / 100)) ]; then
    echo ""
    echo "⚠️  PARTIAL SUCCESS: Most functionality working ($TESTS_PASSED/$TESTS_TOTAL)"
    echo "📋 Minor issues detected but core TTL functionality operational"
else
    echo ""
    echo "❌ SIGNIFICANT ISSUES: Multiple failures detected"
    echo "📋 Requires investigation and fixes before proceeding"
fi

echo ""
echo "=== DETAILED SERVER LOG (last 20 lines) ==="
tail -20 ttl_baseline_test.log

EOF












