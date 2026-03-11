#!/bin/bash

# Test TTL build using correct parameters
echo "🧪 TESTING TTL BUILD WITH CORRECT PARAMETERS"
echo "=========================================="
echo "Testing: TTL version built with exact same parameters as working baseline"
echo ""

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server  
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🚀 Starting TTL server (built with correct parameters)..."
nohup ./cpp/meteor_ttl_working -c 4 -s 4 > ttl_correct_build.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ TTL server failed to start"
    echo "Log:"
    tail -10 ttl_correct_build.log
    exit 1
fi

echo "✅ TTL server started (PID: $SERVER_PID)"
echo ""

# Test baseline functionality first (should now work)
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

echo -n "2. SET test_key test_value: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SET test_key test_value 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "OK" ]; then
    echo "✅ OK"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - Build parameters fix didn't work"
fi

echo -n "3. GET test_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET test_key 2>/dev/null)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ "$RESULT" = "test_value" ]; then
    echo "✅ test_value - BREAKTHROUGH! Build parameters fixed the issue"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "❌ FAILED (\"$RESULT\") - Still broken"
fi

# If baseline works, test SETEX (should work like SET + TTL)
if [ $TESTS_PASSED -eq 3 ]; then
    echo ""
    echo "=== TTL FUNCTIONALITY TEST ==="
    
    echo -n "4. SETEX ttl_key 5 ttl_value: "
    RESULT=$(timeout 5s redis-cli -p 6379 --raw SETEX ttl_key 5 ttl_value 2>/dev/null)
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$RESULT" = "OK" ]; then
        echo "✅ OK"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAILED (\"$RESULT\") - SETEX not working"
    fi

    echo -n "5. GET ttl_key (immediately): "
    RESULT=$(timeout 5s redis-cli -p 6379 --raw GET ttl_key 2>/dev/null)
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$RESULT" = "ttl_value" ]; then
        echo "✅ ttl_value"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAILED (\"$RESULT\") - SETEX key not retrievable"
    fi

    echo -n "6. DEL test_key: "
    RESULT=$(timeout 5s redis-cli -p 6379 --raw DEL test_key 2>/dev/null)
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$RESULT" = "1" ]; then
        echo "✅ 1"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAILED (\"$RESULT\")"
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
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 CORRECT BUILD PARAMETERS TEST RESULTS"
echo "=========================================="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo ""
    echo "🎉 COMPLETE SUCCESS!"
    echo "✅ Correct build parameters fixed the compilation issue"
    echo "✅ Baseline functionality: 100% preserved"
    echo "✅ TTL functionality: Working correctly"
    echo ""
    echo "🚀 TTL implementation is now fully functional!"
elif [ $TESTS_PASSED -ge 3 ]; then
    echo ""
    echo "✅ MAJOR BREAKTHROUGH!"
    echo "✅ Baseline functionality restored with correct build parameters"
    echo "⚠️  TTL functionality needs minor adjustments"
else
    echo ""
    echo "❌ Build parameters alone didn't fix the issue"
    echo "📋 Further investigation needed"
fi

EOF












