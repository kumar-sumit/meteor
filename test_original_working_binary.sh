#!/bin/bash

# Test the original working binary to confirm it doesn't have this issue
echo "🔍 TESTING ORIGINAL WORKING BINARY"
echo "=========================================="
echo "Confirming the original meteor_final_correct works while compiled versions fail"
echo ""

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🚀 Starting ORIGINAL working binary (meteor_final_correct)..."
nohup ./meteor_final_correct -c 4 -s 4 > original_working_test.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Original server failed to start"
    exit 1
fi

echo "✅ Original server started (PID: $SERVER_PID)"
echo ""

# Test the SAME sequence that fails in compiled versions
echo "=== TESTING EXACT SAME SEQUENCE ==="
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

echo -n "2. SET test_key test_value: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SET test_key test_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - CRITICAL: This would confirm binary vs source issue"
fi

echo -n "3. GET test_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET test_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "test_value" ]; then
    echo "✅ test_value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - This is where compiled versions fail"
fi

echo -n "4. DEL test_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw DEL test_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "1" ]; then
    echo "✅ 1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "5. Final PING: "
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
echo "🏆 ORIGINAL BINARY TEST RESULTS"
echo "=========================================="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo ""
    echo "✅ ORIGINAL BINARY: PERFECT (as expected)"
    echo "📋 This confirms the issue is in source compilation, NOT TTL implementation"
    echo "🔧 Solution: Need to identify exact build parameters for working binary"
else
    echo ""
    echo "❌ ORIGINAL BINARY ALSO FAILING"
    echo "📋 This would suggest environmental issues on VM"
fi

EOF












