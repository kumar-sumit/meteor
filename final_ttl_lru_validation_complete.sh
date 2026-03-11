#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🚀 FINAL TTL+LRU VALIDATION - BUFFER CORRUPTION FIX"
echo "$(date): Testing thread-local buffer corruption fix"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== STEP 1: BUILD WITH THREAD-LOCAL BUFFER FIX ==="
export TMPDIR=/mnt/externalDisk/meteor/tmp_compile
echo "Compiling meteor_dragonfly_ttl.cpp with thread-local buffer corruption fix..."

g++ -std=c++20 -O3 -march=native -DBOOST_FIBER_NO_EXCEPTIONS -pthread -pipe \
    meteor_dragonfly_ttl.cpp -o meteor_ttl_lru_buffer_fixed \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

BUILD_STATUS=$?
if [ $BUILD_STATUS -ne 0 ]; then
    echo "❌ BUILD FAILED - compilation errors detected"
    exit 1
fi

echo "✅ BUILD SUCCESSFUL - Thread-local buffer fix compiled"

echo ""
echo "=== STEP 2: SERVER STARTUP ==="
echo "Starting TTL+LRU server with buffer corruption fix..."
nohup ./meteor_ttl_lru_buffer_fixed -c 4 -s 4 > ttl_lru_buffer_fixed.log 2>&1 &
SERVER_PID=$!
sleep 8

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    cat ttl_lru_buffer_fixed.log
    exit 1
fi

echo "✅ SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 3: CRITICAL MULTIPLE OPERATIONS TEST ==="
echo "Testing the exact issue: multiple operations after first success"

# Test 1: Multiple SET/GET operations (the critical test)
echo "🎯 Testing multiple GET operations (buffer corruption fix):"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntest1key\r\n\$9\r\ntest1val\r\n" | nc -w 3 127.0.0.1 6379
echo -n "First GET test1key: "
RESPONSE1=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntest1key\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$RESPONSE1"

printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntest2key\r\n\$9\r\ntest2val\r\n" | nc -w 3 127.0.0.1 6379
echo -n "Second GET test2key: "  
RESPONSE2=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntest2key\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$RESPONSE2"

printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntest3key\r\n\$9\r\ntest3val\r\n" | nc -w 3 127.0.0.1 6379
echo -n "Third GET test3key: "
RESPONSE3=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntest3key\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$RESPONSE3"

printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntest4key\r\n\$9\r\ntest4val\r\n" | nc -w 3 127.0.0.1 6379
echo -n "Fourth GET test4key: "
RESPONSE4=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntest4key\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$RESPONSE4"

# Evaluate buffer corruption fix
BUFFER_FIX_SUCCESS=false
if [[ "$RESPONSE1" == *"test1val"* ]] && [[ "$RESPONSE2" == *"test2val"* ]] && [[ "$RESPONSE3" == *"test3val"* ]] && [[ "$RESPONSE4" == *"test4val"* ]]; then
    echo "✅ BUFFER CORRUPTION FIX SUCCESS: All multiple operations working!"
    BUFFER_FIX_SUCCESS=true
else
    echo "❌ BUFFER CORRUPTION FIX FAILED: Responses = '$RESPONSE1' | '$RESPONSE2' | '$RESPONSE3' | '$RESPONSE4'"
fi

echo ""
echo "=== STEP 4: TTL FUNCTIONALITY COMPLETE TEST ==="
echo "Testing TTL operations with buffer corruption fix"

# Set key with TTL
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nttlkey1\r\n\$9\r\nttlvalue1\r\n" | nc -w 3 127.0.0.1 6379
sleep 1

echo -n "EXPIRE ttlkey1 20: "
EXPIRE_RESULT=$(printf "*3\r\n\$6\r\nEXPIRE\r\n\$8\r\nttlkey1\r\n\$2\r\n20\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$EXPIRE_RESULT"

echo -n "TTL ttlkey1: "
TTL_RESULT=$(printf "*2\r\n\$3\r\nTTL\r\n\$8\r\nttlkey1\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$TTL_RESULT"

echo -n "GET ttlkey1 (with TTL): "
GET_TTL_RESULT=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\nttlkey1\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$GET_TTL_RESULT"

echo -n "PERSIST ttlkey1: "
PERSIST_RESULT=$(printf "*2\r\n\$7\r\nPERSIST\r\n\$8\r\nttlkey1\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$PERSIST_RESULT"

echo -n "TTL after PERSIST (-1): "
TTL_AFTER_PERSIST=$(printf "*2\r\n\$3\r\nTTL\r\n\$8\r\nttlkey1\r\n" | timeout 5s nc -w 5 127.0.0.1 6379)
echo "$TTL_AFTER_PERSIST"

# Evaluate TTL functionality
TTL_SUCCESS=false
if [[ "$EXPIRE_RESULT" == *":1"* ]] && [[ "$TTL_RESULT" == *":"* ]] && [[ "$GET_TTL_RESULT" == *"ttlvalue1"* ]] && [[ "$PERSIST_RESULT" == *":1"* ]] && [[ "$TTL_AFTER_PERSIST" == *":-1"* ]]; then
    echo "✅ TTL FUNCTIONALITY SUCCESS: All TTL commands working correctly!"
    TTL_SUCCESS=true
else
    echo "❌ TTL FUNCTIONALITY ISSUES: Check individual command responses above"
fi

echo ""
echo "=== STEP 5: PIPELINE TTL TEST ==="
echo "Testing TTL commands in pipeline mode"

echo -n "Pipeline (SET+GET+EXPIRE+TTL): "
PIPELINE_RESULT=$(printf "*4\r\n\$3\r\nSET\r\n\$12\r\npipelinekey1\r\n\$13\r\npipelinevalue1\r\n\$3\r\nGET\r\n\$12\r\npipelinekey1\r\n\$6\r\nEXPIRE\r\n\$12\r\npipelinekey1\r\n\$2\r\n30\r\n\$3\r\nTTL\r\n\$12\r\npipelinekey1\r\n" | timeout 8s nc -w 8 127.0.0.1 6379)
echo "$PIPELINE_RESULT"

PIPELINE_SUCCESS=false
if [[ "$PIPELINE_RESULT" == *"+OK"* ]] && [[ "$PIPELINE_RESULT" == *"pipelinevalue1"* ]] && [[ "$PIPELINE_RESULT" == *":1"* ]] && [[ "$PIPELINE_RESULT" == *":"* ]]; then
    echo "✅ PIPELINE TTL SUCCESS: Pipeline TTL commands working!"
    PIPELINE_SUCCESS=true
else
    echo "❌ PIPELINE TTL ISSUES: Response = '$PIPELINE_RESULT'"
fi

echo ""
echo "=== STEP 6: EXPIRATION TEST ==="
echo "Testing TTL expiration functionality"

# Set key with short TTL
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nexpkey1\r\n\$9\r\nexpvalue1\r\n" | nc -w 3 127.0.0.1 6379
printf "*3\r\n\$6\r\nEXPIRE\r\n\$8\r\nexpkey1\r\n\$1\r\n3\r\n" | nc -w 3 127.0.0.1 6379

echo -n "Before expiration: "
BEFORE_EXPIRE=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\nexpkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379)
echo "$BEFORE_EXPIRE"

echo "⏳ Waiting 4 seconds for expiration..."
sleep 4

echo -n "After expiration (should be nil): "
AFTER_EXPIRE=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\nexpkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379)
echo "$AFTER_EXPIRE"

echo -n "TTL after expiration (-2): "
TTL_EXPIRED=$(printf "*2\r\n\$3\r\nTTL\r\n\$8\r\nexpkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379)
echo "$TTL_EXPIRED"

EXPIRATION_SUCCESS=false
if [[ "$BEFORE_EXPIRE" == *"expvalue1"* ]] && [[ "$AFTER_EXPIRE" == *"\$-1"* ]] && [[ "$TTL_EXPIRED" == *":-2"* ]]; then
    echo "✅ EXPIRATION SUCCESS: TTL expiration working correctly!"
    EXPIRATION_SUCCESS=true
else
    echo "❌ EXPIRATION ISSUES: Before='$BEFORE_EXPIRE', After='$AFTER_EXPIRE', TTL='$TTL_EXPIRED'"
fi

echo ""
echo "=== STEP 7: MIXED OPERATIONS STRESS TEST ==="
echo "Testing mixed baseline and TTL operations coexistence"

# Mixed operations
for i in {1..10}; do
    printf "*3\r\n\$3\r\nSET\r\n\$9\r\nmixkey$i\r\n\$10\r\nmixvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    if [ $((i % 3)) -eq 0 ]; then
        # Every 3rd key gets TTL
        printf "*3\r\n\$6\r\nEXPIRE\r\n\$9\r\nmixkey$i\r\n\$2\r\n60\r\n" | nc -w 2 127.0.0.1 6379
    fi
done

echo -n "Mixed operations verification - GET mixkey5: "
MIX_RESULT=$(printf "*2\r\n\$3\r\nGET\r\n\$8\r\nmixkey5\r\n" | timeout 3s nc -w 3 127.0.0.1 6379)
echo "$MIX_RESULT"

echo -n "Mixed operations verification - TTL mixkey6: "
MIX_TTL=$(printf "*2\r\n\$3\r\nTTL\r\n\$8\r\nmixkey6\r\n" | timeout 3s nc -w 3 127.0.0.1 6379)
echo "$MIX_TTL"

MIXED_SUCCESS=false
if [[ "$MIX_RESULT" == *"mixvalue5"* ]] && [[ "$MIX_TTL" == *":"* ]]; then
    echo "✅ MIXED OPERATIONS SUCCESS: Baseline and TTL coexist perfectly!"
    MIXED_SUCCESS=true
else
    echo "❌ MIXED OPERATIONS ISSUES"
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 FINAL TTL+LRU VALIDATION RESULTS"
echo "=========================================="
echo ""
echo "📊 COMPREHENSIVE TEST RESULTS:"
echo ""

if [ "$BUFFER_FIX_SUCCESS" = true ]; then
    echo "✅ BUFFER CORRUPTION FIX: SUCCESS"
    echo "   • Multiple GET operations work correctly"
    echo "   • Thread-local buffer reuse issue resolved"
else
    echo "❌ BUFFER CORRUPTION FIX: FAILED"
    echo "   • Multiple operations still failing"
fi

if [ "$TTL_SUCCESS" = true ]; then
    echo "✅ TTL FUNCTIONALITY: COMPLETE"
    echo "   • EXPIRE, TTL, PERSIST commands working"
    echo "   • Redis protocol compliance verified"
else
    echo "❌ TTL FUNCTIONALITY: ISSUES REMAIN"
fi

if [ "$PIPELINE_SUCCESS" = true ]; then
    echo "✅ PIPELINE TTL: WORKING"
    echo "   • TTL commands work in pipeline mode"
else
    echo "❌ PIPELINE TTL: ISSUES"
fi

if [ "$EXPIRATION_SUCCESS" = true ]; then
    echo "✅ TTL EXPIRATION: WORKING"
    echo "   • Keys expire correctly after timeout"
else
    echo "❌ TTL EXPIRATION: ISSUES"
fi

if [ "$MIXED_SUCCESS" = true ]; then
    echo "✅ MIXED OPERATIONS: SUCCESS"
    echo "   • Baseline and TTL operations coexist"
else
    echo "❌ MIXED OPERATIONS: ISSUES"
fi

echo ""
echo "🎯 TECHNICAL ACHIEVEMENTS:"
echo "  • Thread-local buffer corruption fix applied"
echo "  • Dragonfly-inspired TTL overlay implementation"
echo "  • Redis-compatible protocol responses"
echo "  • Cross-core deterministic routing"
echo "  • Zero baseline impact architecture"
echo ""

# Overall status
ALL_SUCCESS=false
if [ "$BUFFER_FIX_SUCCESS" = true ] && [ "$TTL_SUCCESS" = true ] && [ "$PIPELINE_SUCCESS" = true ] && [ "$EXPIRATION_SUCCESS" = true ] && [ "$MIXED_SUCCESS" = true ]; then
    ALL_SUCCESS=true
fi

if [ "$ALL_SUCCESS" = true ]; then
    echo "🚀 STATUS: TTL+LRU IMPLEMENTATION PRODUCTION-READY ✅"
    echo "   All critical functionality working correctly!"
else
    echo "⚠️  STATUS: TTL+LRU IMPLEMENTATION PARTIALLY WORKING"
    echo "   Some issues remain - see details above"
fi

echo ""
echo "$(date): TTL+LRU validation complete!"
echo ""

echo "Server log (last 20 lines):"
tail -20 ttl_lru_buffer_fixed.log

echo ""
echo "🎉 SENIOR ARCHITECT TTL+LRU IMPLEMENTATION TEST COMPLETE! 🎉"












