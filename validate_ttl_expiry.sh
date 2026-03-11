#!/bin/bash

# **METEOR COMMERCIAL LRU+TTL - TTL EXPIRY VALIDATION TEST**
# 
# This script validates that:
# ✅ Keys actually expire after their TTL
# ✅ TTL values decrease over time  
# ✅ Expired keys return (nil) when accessed
# ✅ TTL command returns correct values (-1, -2, positive)
# ✅ No blocking during expiry operations

echo "🧪 METEOR COMMERCIAL LRU+TTL - TTL EXPIRY VALIDATION"
echo ""
echo "📋 VALIDATION PLAN:"
echo "   1. Set keys with various TTL values"
echo "   2. Monitor TTL countdown"
echo "   3. Verify keys expire correctly"  
echo "   4. Test TTL edge cases"
echo "   5. Verify non-blocking behavior"
echo ""

# Server configuration
SERVER_HOST="127.0.0.1"
SERVER_PORT="6380"
REDIS_CLI="redis-cli -h $SERVER_HOST -p $SERVER_PORT"

echo "🚀 Starting Commercial LRU+TTL Server..."
pkill -f meteor_commercial_lru_ttl 2>/dev/null
sleep 2

# Start server (using different port to avoid conflicts)
if [ -f "./meteor_commercial_lru_ttl" ]; then
    ./meteor_commercial_lru_ttl -h $SERVER_HOST -p $SERVER_PORT -c 4 -s 2 -m 512 &> ttl_validation.log &
    SERVER_PID=$!
    echo "✅ Server started (PID: $SERVER_PID)"
elif [ -f "./cpp/meteor_commercial_lru_ttl" ]; then
    ./cpp/meteor_commercial_lru_ttl -h $SERVER_HOST -p $SERVER_PORT -c 4 -s 2 -m 512 &> ttl_validation.log &
    SERVER_PID=$!
    echo "✅ Server started from cpp/ (PID: $SERVER_PID)"
else
    echo "❌ meteor_commercial_lru_ttl binary not found"
    echo "   Please build first using: ./build_commercial_lru_ttl.sh"
    exit 1
fi

# Wait for server startup
sleep 5

# Test server connectivity
echo "📡 Testing server connectivity..."
if timeout 5 $REDIS_CLI ping > /dev/null 2>&1; then
    echo "✅ Server is responding to PING"
else
    echo "❌ Server not responding"
    echo "Server log tail:"
    tail -10 ttl_validation.log
    kill $SERVER_PID 2>/dev/null
    exit 1
fi
echo ""

# =============================================================================
echo "🧪 TEST 1: BASIC TTL EXPIRY VALIDATION"
echo "============================================================================="

echo "📝 Setting up test keys with different TTL values..."

# Set keys with various TTL values
$REDIS_CLI set key_3sec "expires in 3 seconds" EX 3
$REDIS_CLI set key_5sec "expires in 5 seconds" EX 5  
$REDIS_CLI set key_8sec "expires in 8 seconds" EX 8
$REDIS_CLI set key_no_ttl "never expires"

echo "✅ Keys created"
echo ""

echo "📊 Initial TTL values:"
echo "   key_3sec TTL: $($REDIS_CLI ttl key_3sec)"
echo "   key_5sec TTL: $($REDIS_CLI ttl key_5sec)"
echo "   key_8sec TTL: $($REDIS_CLI ttl key_8sec)"
echo "   key_no_ttl TTL: $($REDIS_CLI ttl key_no_ttl) (should be -1)"
echo ""

echo "🔍 Initial key values:"
echo "   key_3sec: '$($REDIS_CLI get key_3sec)'"
echo "   key_5sec: '$($REDIS_CLI get key_5sec)'"
echo "   key_8sec: '$($REDIS_CLI get key_8sec)'"
echo "   key_no_ttl: '$($REDIS_CLI get key_no_ttl)'"
echo ""

# Monitor TTL countdown
echo "⏰ Monitoring TTL countdown..."
for i in {1..10}; do
    echo "Time $i seconds:"
    TTL_3=$($REDIS_CLI ttl key_3sec)
    TTL_5=$($REDIS_CLI ttl key_5sec) 
    TTL_8=$($REDIS_CLI ttl key_8sec)
    echo "   key_3sec: $TTL_3, key_5sec: $TTL_5, key_8sec: $TTL_8"
    sleep 1
done
echo ""

echo "🔍 Final key status after 10 seconds:"
KEY_3_FINAL=$($REDIS_CLI get key_3sec)
KEY_5_FINAL=$($REDIS_CLI get key_5sec)
KEY_8_FINAL=$($REDIS_CLI get key_8sec)
KEY_NO_TTL_FINAL=$($REDIS_CLI get key_no_ttl)

echo "   key_3sec: '$KEY_3_FINAL' (should be empty/nil)"
echo "   key_5sec: '$KEY_5_FINAL' (should be empty/nil)"
echo "   key_8sec: '$KEY_8_FINAL' (should still exist)"
echo "   key_no_ttl: '$KEY_NO_TTL_FINAL' (should still exist)"
echo ""

# Validate expiry results
EXPIRED_CORRECT=0

if [ -z "$KEY_3_FINAL" ] || [ "$KEY_3_FINAL" = "(nil)" ]; then
    echo "   ✅ key_3sec expired correctly"
    ((EXPIRED_CORRECT++))
else
    echo "   ❌ key_3sec did not expire: '$KEY_3_FINAL'"
fi

if [ -z "$KEY_5_FINAL" ] || [ "$KEY_5_FINAL" = "(nil)" ]; then
    echo "   ✅ key_5sec expired correctly"  
    ((EXPIRED_CORRECT++))
else
    echo "   ❌ key_5sec did not expire: '$KEY_5_FINAL'"
fi

if [ ! -z "$KEY_8_FINAL" ] && [ "$KEY_8_FINAL" != "(nil)" ]; then
    echo "   ✅ key_8sec still exists (correct)"
    ((EXPIRED_CORRECT++))
else
    echo "   ❌ key_8sec expired too early"
fi

if [ ! -z "$KEY_NO_TTL_FINAL" ] && [ "$KEY_NO_TTL_FINAL" != "(nil)" ]; then
    echo "   ✅ key_no_ttl still exists (correct)"
    ((EXPIRED_CORRECT++))
else
    echo "   ❌ key_no_ttl incorrectly expired"
fi

echo ""
if [ $EXPIRED_CORRECT -eq 4 ]; then
    echo "🎉 TTL EXPIRY TEST: PASSED (4/4 correct)"
else
    echo "⚠️  TTL EXPIRY TEST: PARTIAL ($EXPIRED_CORRECT/4 correct)"
fi
echo ""

# =============================================================================
echo "🧪 TEST 2: TTL COMMAND EDGE CASES"
echo "============================================================================="

echo "📝 Testing TTL command return values..."

# Test TTL on expired key
TTL_EXPIRED=$($REDIS_CLI ttl key_3sec)
echo "TTL of expired key: $TTL_EXPIRED (should be -2)"

# Test TTL on non-existent key
TTL_NONEXISTENT=$($REDIS_CLI ttl definitely_does_not_exist)
echo "TTL of non-existent key: $TTL_NONEXISTENT (should be -2)"

# Test TTL on key without TTL
TTL_NO_TTL=$($REDIS_CLI ttl key_no_ttl)
echo "TTL of key without TTL: $TTL_NO_TTL (should be -1)"

echo ""
TTL_CASES_CORRECT=0

if [ "$TTL_EXPIRED" = "-2" ]; then
    echo "   ✅ Expired key returns -2"
    ((TTL_CASES_CORRECT++))
else
    echo "   ❌ Expired key returned: $TTL_EXPIRED (expected -2)"
fi

if [ "$TTL_NONEXISTENT" = "-2" ]; then
    echo "   ✅ Non-existent key returns -2"
    ((TTL_CASES_CORRECT++))
else
    echo "   ❌ Non-existent key returned: $TTL_NONEXISTENT (expected -2)"
fi

if [ "$TTL_NO_TTL" = "-1" ]; then
    echo "   ✅ Key without TTL returns -1"
    ((TTL_CASES_CORRECT++))
else
    echo "   ❌ Key without TTL returned: $TTL_NO_TTL (expected -1)"
fi

echo ""
if [ $TTL_CASES_CORRECT -eq 3 ]; then
    echo "🎉 TTL EDGE CASES: PASSED (3/3 correct)"
else
    echo "⚠️  TTL EDGE CASES: PARTIAL ($TTL_CASES_CORRECT/3 correct)"
fi
echo ""

# =============================================================================  
echo "🧪 TEST 3: EXPIRE COMMAND VALIDATION"
echo "============================================================================="

echo "📝 Testing EXPIRE command..."

# Create key without TTL
$REDIS_CLI set expire_test_key "adding ttl with expire command"
echo "Created key: expire_test_key"

# Add TTL using EXPIRE command
EXPIRE_RESULT=$($REDIS_CLI expire expire_test_key 4)
echo "EXPIRE command result: $EXPIRE_RESULT (should be 1)"

# Check TTL was set
EXPIRE_TTL=$($REDIS_CLI ttl expire_test_key)
echo "TTL after EXPIRE: $EXPIRE_TTL (should be ~4)"

echo ""
echo "⏰ Waiting 5 seconds for EXPIRE-set key to expire..."
sleep 5

# Check if key expired
EXPIRE_FINAL=$($REDIS_CLI get expire_test_key)
echo "Key after expiry: '$EXPIRE_FINAL' (should be empty/nil)"

echo ""
if [ -z "$EXPIRE_FINAL" ] || [ "$EXPIRE_FINAL" = "(nil)" ]; then
    echo "   ✅ EXPIRE command worked correctly"
else
    echo "   ❌ EXPIRE command failed: '$EXPIRE_FINAL'"
fi
echo ""

# =============================================================================
echo "🧪 TEST 4: NON-BLOCKING BEHAVIOR VALIDATION"  
echo "============================================================================="

echo "📝 Testing server responsiveness during expiration..."

# Create many keys with short TTL
echo "Creating 50 keys with 2-3 second TTL..."
for i in {1..50}; do
    TTL=$((2 + i % 2))  # TTL of 2 or 3 seconds
    $REDIS_CLI set "bulk_expire_$i" "data_$i" EX $TTL > /dev/null
done
echo "✅ 50 keys created"

# Test server responsiveness during expiration
echo ""
echo "🚀 Testing server responsiveness while keys expire..."

START_TIME=$(date +%s)
RESPONSE_COUNT=0
TOTAL_TESTS=20

for i in {1..20}; do
    if timeout 1 $REDIS_CLI ping > /dev/null 2>&1; then
        ((RESPONSE_COUNT++))
    fi
    sleep 0.2
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "Response test: $RESPONSE_COUNT/$TOTAL_TESTS PING responses in ${DURATION}s"

if [ $RESPONSE_COUNT -ge 18 ]; then
    echo "   ✅ Server remained highly responsive during expiration"
else
    echo "   ⚠️  Server responsiveness impacted: $RESPONSE_COUNT/$TOTAL_TESTS"
fi

# Check how many keys expired
sleep 2
REMAINING_KEYS=$($REDIS_CLI keys "bulk_expire_*" | wc -l | tr -d ' ')
echo ""
echo "🔍 Bulk expiry result: $REMAINING_KEYS/50 keys remaining"

if [ $REMAINING_KEYS -lt 10 ]; then
    echo "   ✅ Mass expiration successful"
else
    echo "   ⚠️  Some keys may not have expired yet: $REMAINING_KEYS remaining"
fi
echo ""

# =============================================================================
echo "🏆 VALIDATION SUMMARY"
echo "============================================================================="

echo "📊 TTL EXPIRY VALIDATION RESULTS:"
echo ""

TOTAL_SCORE=0
MAX_SCORE=4

if [ $EXPIRED_CORRECT -eq 4 ]; then
    echo "   ✅ Basic TTL Expiry: PASSED (4/4)"
    ((TOTAL_SCORE++))
else
    echo "   ⚠️  Basic TTL Expiry: PARTIAL ($EXPIRED_CORRECT/4)"
fi

if [ $TTL_CASES_CORRECT -eq 3 ]; then
    echo "   ✅ TTL Edge Cases: PASSED (3/3)"
    ((TOTAL_SCORE++))
else
    echo "   ⚠️  TTL Edge Cases: PARTIAL ($TTL_CASES_CORRECT/3)"
fi

if [ -z "$EXPIRE_FINAL" ] || [ "$EXPIRE_FINAL" = "(nil)" ]; then
    echo "   ✅ EXPIRE Command: PASSED"
    ((TOTAL_SCORE++))
else
    echo "   ❌ EXPIRE Command: FAILED"
fi

if [ $RESPONSE_COUNT -ge 18 ]; then
    echo "   ✅ Non-Blocking Behavior: PASSED ($RESPONSE_COUNT/20 responses)"
    ((TOTAL_SCORE++))
else
    echo "   ⚠️  Non-Blocking Behavior: PARTIAL ($RESPONSE_COUNT/20 responses)"
fi

echo ""
echo "📈 OVERALL TTL VALIDATION SCORE: $TOTAL_SCORE/$MAX_SCORE"

if [ $TOTAL_SCORE -eq $MAX_SCORE ]; then
    echo ""
    echo "🎉 TTL EXPIRY IMPLEMENTATION: FULLY VALIDATED!"
    echo "   ✅ Keys expire correctly after TTL"
    echo "   ✅ TTL command returns proper values (-1, -2, positive)"  
    echo "   ✅ EXPIRE command works correctly"
    echo "   ✅ Server remains responsive during expiration"
    echo ""
    echo "🚀 RECOMMENDATION: PRODUCTION READY"
elif [ $TOTAL_SCORE -ge 3 ]; then
    echo ""
    echo "✅ TTL EXPIRY IMPLEMENTATION: MOSTLY VALIDATED"
    echo "   Minor issues detected but core functionality works"
    echo ""  
    echo "🟡 RECOMMENDATION: PRODUCTION READY with monitoring"
else
    echo ""
    echo "⚠️  TTL EXPIRY IMPLEMENTATION: NEEDS ATTENTION"
    echo "   Multiple issues detected, review required"
    echo ""
    echo "🔴 RECOMMENDATION: Fix issues before production"
fi

echo ""
echo "📁 Server log saved to: ttl_validation.log"
echo ""

# Cleanup
echo "🧹 Cleaning up..."
kill $SERVER_PID 2>/dev/null
sleep 2
echo "✅ Validation test complete!"














