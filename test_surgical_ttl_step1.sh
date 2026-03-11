#!/bin/bash

# Test Surgical TTL Step 1: TTL Command Detection
echo "🧪 SURGICAL TTL STEP 1 TEST"
echo "=========================================="
echo "Testing: TTL command detection with baseline preservation"
echo ""

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== STEP 1: TTL COMMAND DETECTION TEST ==="
echo "$(date): Starting surgical test"

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 3

# Start surgical TTL server
echo "🚀 Starting surgical TTL server..."
nohup ./meteor_surgical_test -c 4 -s 4 > surgical_test.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    tail -10 surgical_test.log
    exit 1
fi

echo "✅ Server started (PID: $SERVER_PID)"
echo ""

# Test baseline functionality (MUST preserve correctness)
echo "=== BASELINE VERIFICATION ==="
TESTS_PASSED=0
TESTS_TOTAL=0

echo -n "1. PING: "
PING_TEST=$(timeout 5s redis-cli -p 6379 PING 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ $? -eq 0 ] && [ "$PING_TEST" = "PONG" ]; then
    echo "✅ PONG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED ($PING_TEST)"
fi

echo -n "2. SET test_key test_value: "
SET_TEST=$(timeout 5s redis-cli -p 6379 SET test_key test_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ $? -eq 0 ] && [ "$SET_TEST" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED ($SET_TEST)"
fi

echo -n "3. GET test_key: "
GET_TEST=$(timeout 5s redis-cli -p 6379 GET test_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ $? -eq 0 ] && [ "$GET_TEST" = "test_value" ]; then
    echo "✅ test_value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED ($GET_TEST)"
fi

echo -n "4. DEL test_key: "
DEL_TEST=$(timeout 5s redis-cli -p 6379 DEL test_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ $? -eq 0 ] && [ "$DEL_TEST" = "1" ]; then
    echo "✅ 1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED ($DEL_TEST)"
fi

echo ""
echo "=== NEW FEATURE VERIFICATION: TTL COMMAND ==="

echo -n "5. TTL non_existent_key: "
TTL_TEST=$(timeout 5s redis-cli -p 6379 TTL non_existent_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ $? -eq 0 ] && [ "$TTL_TEST" = "-2" ]; then
    echo "✅ -2 (key not found)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED ($TTL_TEST)"
fi

# Test another baseline operation after TTL to ensure no interference
echo -n "6. PING after TTL: "
PING_TEST2=$(timeout 5s redis-cli -p 6379 PING 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ $? -eq 0 ] && [ "$PING_TEST2" = "PONG" ]; then
    echo "✅ PONG"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED ($PING_TEST2)"
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 SURGICAL STEP 1 RESULTS"
echo "=========================================="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo ""
    echo "🎉 SURGICAL STEP 1: SUCCESS!"
    echo "✅ All baseline functionality preserved"
    echo "✅ TTL command detection working"
    echo "✅ Ready for Step 2: Actual TTL functionality"
    exit 0
else
    echo ""
    echo "❌ SURGICAL STEP 1: FAILED"
    echo "🔧 Issues detected - must fix before proceeding"
    echo ""
    echo "Server log (last 20 lines):"
    tail -20 surgical_test.log
    exit 1
fi

EOF












