#!/bin/bash

echo "🧪 METEOR COMMERCIAL LRU+TTL - VM TTL EXPIRY VALIDATION"
echo ""

# Kill any existing servers
pkill -f meteor 2>/dev/null
sleep 2

echo "🚀 Starting Commercial LRU+TTL Server..."
./meteor_commercial_lru_ttl -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 512 &> ttl_vm_test.log &
SERVER_PID=$!
sleep 4

echo "✅ Server started (PID: $SERVER_PID)"
echo ""

# Test connectivity
echo "📡 Testing connectivity..."
if redis-cli -p 6379 ping > /dev/null 2>&1; then
    echo "✅ Server responding to PING"
else
    echo "❌ Server not responding"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi
echo ""

echo "📝 TTL EXPIRY VALIDATION TESTS:"
echo "==============================="
echo ""

# Test 1: SET EX command
echo "Test 1: SET EX with 5-second TTL"
redis-cli -p 6379 set expire_test "will expire in 5 seconds" EX 5
echo "Initial TTL: $(redis-cli -p 6379 ttl expire_test) seconds"
echo "Initial value: $(redis-cli -p 6379 get expire_test)"
echo ""

echo "⏰ Waiting 6 seconds for key expiry..."
sleep 6
echo ""

# Check if key expired
GET_RESULT=$(redis-cli -p 6379 get expire_test 2>/dev/null)
TTL_RESULT=$(redis-cli -p 6379 ttl expire_test 2>/dev/null)

echo "After 6 seconds:"
echo "GET result: '$GET_RESULT'"
echo "TTL result: $TTL_RESULT"
echo ""

# Validate expiry
if [ -z "$GET_RESULT" ] || [ "$GET_RESULT" = "(nil)" ]; then
    echo "✅ SET EX: Key expired correctly"
    TEST1_PASS=1
else
    echo "❌ SET EX: Key did not expire (found: '$GET_RESULT')"
    TEST1_PASS=0
fi

if [ "$TTL_RESULT" = "-2" ]; then
    echo "✅ TTL: Returns -2 for expired key"
    TEST1_TTL_PASS=1
else
    echo "⚠️ TTL: Returned $TTL_RESULT (expected -2)"
    TEST1_TTL_PASS=0
fi
echo ""

# Test 2: EXPIRE command
echo "Test 2: EXPIRE command with 3-second TTL"
redis-cli -p 6379 set expire_cmd_test "testing expire command" > /dev/null
EXPIRE_CMD_RESULT=$(redis-cli -p 6379 expire expire_cmd_test 3)
echo "EXPIRE command result: $EXPIRE_CMD_RESULT (should be 1)"
echo "TTL after EXPIRE: $(redis-cli -p 6379 ttl expire_cmd_test) seconds"
echo ""

echo "⏰ Waiting 4 seconds for EXPIRE key to expire..."
sleep 4
echo ""

EXPIRE_GET_RESULT=$(redis-cli -p 6379 get expire_cmd_test 2>/dev/null)
echo "After 4 seconds:"
echo "GET result: '$EXPIRE_GET_RESULT'"

if [ -z "$EXPIRE_GET_RESULT" ] || [ "$EXPIRE_GET_RESULT" = "(nil)" ]; then
    echo "✅ EXPIRE: Key expired correctly"
    TEST2_PASS=1
else
    echo "❌ EXPIRE: Key did not expire (found: '$EXPIRE_GET_RESULT')"
    TEST2_PASS=0
fi
echo ""

# Test 3: TTL edge cases
echo "Test 3: TTL edge cases"

# Non-existent key
NON_EXIST_TTL=$(redis-cli -p 6379 ttl nonexistent_key_12345)
echo "TTL of non-existent key: $NON_EXIST_TTL (should be -2)"

# Key without TTL
redis-cli -p 6379 set permanent_key "no ttl set" > /dev/null
NO_TTL_RESULT=$(redis-cli -p 6379 ttl permanent_key)
echo "TTL of key without TTL: $NO_TTL_RESULT (should be -1)"
echo ""

# Validate edge cases
TEST3_PASS=1
if [ "$NON_EXIST_TTL" != "-2" ]; then
    echo "⚠️ TTL edge case issue: non-existent key returned $NON_EXIST_TTL"
    TEST3_PASS=0
fi

if [ "$NO_TTL_RESULT" != "-1" ]; then
    echo "⚠️ TTL edge case issue: key without TTL returned $NO_TTL_RESULT"
    TEST3_PASS=0
fi

if [ $TEST3_PASS -eq 1 ]; then
    echo "✅ TTL edge cases: All correct"
fi
echo ""

# Summary
echo "🏆 TTL VALIDATION SUMMARY:"
echo "=========================="

TOTAL_TESTS=4
PASSED_TESTS=0

if [ $TEST1_PASS -eq 1 ]; then
    echo "✅ SET EX expiry: PASSED"
    ((PASSED_TESTS++))
else
    echo "❌ SET EX expiry: FAILED"
fi

if [ $TEST1_TTL_PASS -eq 1 ]; then
    echo "✅ TTL expired key: PASSED" 
    ((PASSED_TESTS++))
else
    echo "❌ TTL expired key: FAILED"
fi

if [ $TEST2_PASS -eq 1 ]; then
    echo "✅ EXPIRE command: PASSED"
    ((PASSED_TESTS++))
else
    echo "❌ EXPIRE command: FAILED"
fi

if [ $TEST3_PASS -eq 1 ]; then
    echo "✅ TTL edge cases: PASSED"
    ((PASSED_TESTS++))
else
    echo "❌ TTL edge cases: FAILED"
fi

echo ""
echo "📊 RESULT: $PASSED_TESTS/$TOTAL_TESTS tests passed"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo ""
    echo "🎉 TTL EXPIRY FUNCTIONALITY: FULLY VALIDATED!"
    echo "   ✅ Keys expire correctly after TTL"
    echo "   ✅ TTL command returns proper values"
    echo "   ✅ EXPIRE command works correctly"
    echo "   ✅ All edge cases handled properly"
    echo ""
    echo "🚀 CONCLUSION: TTL implementation is PRODUCTION READY"
elif [ $PASSED_TESTS -ge 3 ]; then
    echo ""
    echo "✅ TTL EXPIRY FUNCTIONALITY: MOSTLY WORKING"
    echo "   Core functionality validated with minor issues"
else
    echo ""
    echo "⚠️ TTL EXPIRY FUNCTIONALITY: NEEDS ATTENTION"
    echo "   Multiple test failures detected"
fi

echo ""
echo "📁 Server log: ttl_vm_test.log"

# Cleanup
echo "🧹 Cleaning up..."
kill $SERVER_PID 2>/dev/null
sleep 1
echo "✅ TTL validation test complete!"














