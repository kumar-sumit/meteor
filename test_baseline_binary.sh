#!/bin/bash

# Test the meteor_final_correct binary that the user said works perfectly
echo "🧪 TESTING BASELINE BINARY: meteor_final_correct"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Check if meteor_final_correct exists
echo "=== CHECKING BASELINE BINARY ==="
if [ -f "meteor_final_correct" ]; then
    ls -la meteor_final_correct
    file meteor_final_correct
    echo "✅ meteor_final_correct binary found"
elif [ -f "cpp/meteor_final_correct" ]; then
    ls -la cpp/meteor_final_correct
    file cpp/meteor_final_correct
    echo "✅ meteor_final_correct binary found in cpp/"
    # Copy it to current directory for easier access
    cp cpp/meteor_final_correct ./
else
    echo "❌ meteor_final_correct binary not found"
    echo "Looking for any meteor binaries..."
    find . -name "*meteor*" -type f -executable 2>/dev/null | head -10
    exit 1
fi

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "🚀 Starting meteor_final_correct (the working baseline)..."
nohup ./meteor_final_correct -c 4 -s 4 > baseline_test.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Baseline server failed to start"
    echo "Log:"
    tail -10 baseline_test.log
    exit 1
fi

echo "✅ Baseline server started (PID: $SERVER_PID)"
echo ""

# Test baseline functionality
echo "=== BASELINE FUNCTIONALITY TEST ==="
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

echo -n "2. SET baseline_key baseline_value: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SET baseline_key baseline_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "3. GET baseline_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET baseline_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "baseline_value" ]; then
    echo "✅ baseline_value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\")"
fi

echo -n "4. DEL baseline_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw DEL baseline_key 2>/dev/null)
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
echo "🏆 BASELINE BINARY TEST RESULTS"  
echo "=========================================="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo ""
    echo "🎉 BASELINE BINARY WORKS PERFECTLY!"
    echo "✅ This confirms the issue is with my source compilation, not baseline binary"
    echo "📋 Action needed: Use this working binary as reference for TTL implementation"
else
    echo ""
    echo "❌ BASELINE BINARY ALSO HAS ISSUES"
    echo "📋 This suggests environmental or system-level problems"
fi

EOF












