#!/bin/bash

# Surgical TTL Implementation Testing
# Test each incremental change immediately

STEP_NAME="$1"
EXPECTED_RESULT="$2"

echo "=========================================="
echo "🔧 SURGICAL TTL - STEP: $STEP_NAME"
echo "$(date): Testing incremental change"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << EOF

cd /mnt/externalDisk/meteor

echo "=== STEP: $STEP_NAME ==="

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 3

# Build the current surgical version
echo "🔧 Building surgical TTL version..."
g++ -std=c++20 -O2 -DNDEBUG -DBOOST_FIBER_NO_EXCEPTIONS -pthread \
    meteor_ttl_surgical.cpp -o meteor_surgical_test \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

if [ \$? -ne 0 ]; then
    echo "❌ BUILD FAILED"
    exit 1
fi

echo "✅ Build successful"

# Start server
echo "🚀 Starting surgical TTL server..."
nohup ./meteor_surgical_test -c 4 -s 4 > surgical_test.log 2>&1 &
SERVER_PID=\$!
sleep 5

if ! ps -p \$SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    tail -10 surgical_test.log
    exit 1
fi

echo "✅ Server started (PID: \$SERVER_PID)"

# Test core functionality (should never break)
echo ""
echo "=== BASELINE VERIFICATION ==="
echo -n "PING: "
PING_TEST=\$(timeout 3s redis-cli -p 6379 PING 2>/dev/null)
if [ \$? -eq 0 ] && [ "\$PING_TEST" = "PONG" ]; then
    echo "✅ PONG"
    PING_OK=true
else
    echo "❌ FAILED (\$PING_TEST)"
    PING_OK=false
fi

echo -n "SET baseline_key baseline_value: "
SET_TEST=\$(timeout 3s redis-cli -p 6379 SET baseline_key baseline_value 2>/dev/null)
if [ \$? -eq 0 ] && [ "\$SET_TEST" = "OK" ]; then
    echo "✅ OK"
    SET_OK=true
else
    echo "❌ FAILED (\$SET_TEST)"
    SET_OK=false
fi

echo -n "GET baseline_key: "
GET_TEST=\$(timeout 3s redis-cli -p 6379 GET baseline_key 2>/dev/null)
if [ \$? -eq 0 ] && [ "\$GET_TEST" = "baseline_value" ]; then
    echo "✅ baseline_value"
    GET_OK=true
else
    echo "❌ FAILED (\$GET_TEST)"
    GET_OK=false
fi

echo -n "DEL baseline_key: "
DEL_TEST=\$(timeout 3s redis-cli -p 6379 DEL baseline_key 2>/dev/null)
if [ \$? -eq 0 ] && [ "\$DEL_TEST" = "1" ]; then
    echo "✅ 1"
    DEL_OK=true
else
    echo "❌ FAILED (\$DEL_TEST)"
    DEL_OK=false
fi

# Test the new functionality for this step
echo ""
echo "=== STEP VERIFICATION: $STEP_NAME ==="
if [ "$STEP_NAME" = "TTL_COMMAND_DETECTION" ]; then
    echo -n "TTL unknown_key: "
    TTL_TEST=\$(timeout 3s redis-cli -p 6379 TTL unknown_key 2>/dev/null)
    echo "\$TTL_TEST (expecting: $EXPECTED_RESULT)"
    
    if [ "\$TTL_TEST" = "$EXPECTED_RESULT" ]; then
        echo "✅ TTL COMMAND: Working correctly"
        STEP_OK=true
    else
        echo "❌ TTL COMMAND: Not working as expected"
        STEP_OK=false
    fi
fi

# Stop server
kill \$SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 SURGICAL STEP RESULTS"
echo "=========================================="

TOTAL_TESTS=4
PASSED_TESTS=0

[ "\$PING_OK" = true ] && echo "✅ PING: Preserved" && PASSED_TESTS=\$((PASSED_TESTS + 1)) || echo "❌ PING: BROKEN"
[ "\$SET_OK" = true ] && echo "✅ SET: Preserved" && PASSED_TESTS=\$((PASSED_TESTS + 1)) || echo "❌ SET: BROKEN"  
[ "\$GET_OK" = true ] && echo "✅ GET: Preserved" && PASSED_TESTS=\$((PASSED_TESTS + 1)) || echo "❌ GET: BROKEN"
[ "\$DEL_OK" = true ] && echo "✅ DEL: Preserved" && PASSED_TESTS=\$((PASSED_TESTS + 1)) || echo "❌ DEL: BROKEN"

if [ "\$STEP_OK" = true ]; then
    echo "✅ NEW FEATURE: $STEP_NAME working correctly"
    TOTAL_TESTS=\$((TOTAL_TESTS + 1))
    PASSED_TESTS=\$((PASSED_TESTS + 1))
else
    echo "❌ NEW FEATURE: $STEP_NAME not working"
    TOTAL_TESTS=\$((TOTAL_TESTS + 1))
fi

echo ""
echo "Overall: \$PASSED_TESTS/\$TOTAL_TESTS tests passing"

if [ "\$PASSED_TESTS" -eq "\$TOTAL_TESTS" ]; then
    echo ""
    echo "🎉 STEP SUCCESS: $STEP_NAME"
    echo "✅ Baseline preserved + New functionality working"
    echo "✅ Ready for next surgical step"
    exit 0
else
    echo ""
    echo "❌ STEP FAILED: $STEP_NAME"
    echo "🔧 Must fix before proceeding to next step"
    exit 1
fi

EOF

echo ""
echo "Surgical step test completed: $STEP_NAME"












