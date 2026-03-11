#!/bin/bash

# **METEOR REDIS COMPATIBILITY TEST SUITE**
# Tests Meteor server compatibility with standard Redis clients
# Usage: ./redis_compatibility_test.sh [host] [port]

HOST=${1:-127.0.0.1}
PORT=${2:-6379}

echo "🧪 **METEOR REDIS COMPATIBILITY TEST SUITE**"
echo "======================================="
echo "Target Server: $HOST:$PORT"
echo "Timestamp: $(date)"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Function to run redis-cli command and check result
run_test() {
    local test_name="$1"
    local command="$2"
    local expected="$3"
    local description="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo "🔹 TEST $TOTAL_TESTS: $test_name"
    echo "   Command: $command"
    echo "   Expected: $expected"
    echo "   Description: $description"
    
    # Run command and capture output
    result=$(redis-cli -h $HOST -p $PORT -c "$command" 2>&1)
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "   ❌ FAILED: Connection error - $result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo ""
        return 1
    fi
    
    # Clean up result (remove quotes and whitespace)
    result=$(echo "$result" | tr -d '"' | xargs)
    expected=$(echo "$expected" | tr -d '"' | xargs)
    
    if [ "$result" = "$expected" ] || [[ "$result" =~ $expected ]]; then
        echo "   ✅ PASSED: Got '$result'"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "   ❌ FAILED: Got '$result', expected '$expected'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    echo ""
}

# Function to run command without checking result (for setup)
run_command() {
    local command="$1"
    redis-cli -h $HOST -p $PORT -c "$command" >/dev/null 2>&1
}

echo "🚀 **BASIC CONNECTIVITY TEST**"
echo "------------------------------"

# Test server connectivity
run_test "PING" "PING" "PONG" "Basic server connectivity"

echo "📝 **BASIC SET/GET OPERATIONS**"
echo "--------------------------------"

# Basic SET/GET operations
run_test "SET_STRING" "SET mykey myvalue" "OK" "Set a string value"
run_test "GET_STRING" "GET mykey" "myvalue" "Get the string value back"

# Overwrite existing key
run_test "SET_OVERWRITE" "SET mykey newvalue" "OK" "Overwrite existing key"
run_test "GET_OVERWRITE" "GET mykey" "newvalue" "Get overwritten value"

# GET non-existent key
run_test "GET_MISSING" "GET nonexistent" "(nil)" "Get non-existent key should return nil"

echo "🗑️  **DELETE OPERATIONS**"
echo "-------------------------"

run_test "DEL_EXISTING" "DEL mykey" "1" "Delete existing key should return 1"
run_test "GET_DELETED" "GET mykey" "(nil)" "Get deleted key should return nil"
run_test "DEL_MISSING" "DEL nonexistent" "0" "Delete non-existent key should return 0"

echo "⏰ **TTL OPERATIONS (SETEX)**"
echo "------------------------------"

# SETEX operations
run_test "SETEX_BASIC" "SETEX tempkey 60 tempvalue" "OK" "Set key with 60 second expiry"
run_test "GET_SETEX" "GET tempkey" "tempvalue" "Get SETEX key should return value"

# TTL should be between 55-60 seconds
run_command "SETEX ttltest 30 ttlvalue"
sleep 1
result=$(redis-cli -h $HOST -p $PORT -c "TTL ttltest" 2>&1)
if [[ "$result" -ge 25 && "$result" -le 30 ]]; then
    echo "🔹 TEST $((TOTAL_TESTS + 1)): TTL_CHECK"
    echo "   Command: TTL ttltest"
    echo "   Expected: 25-30 seconds"
    echo "   Description: TTL should return remaining seconds"
    echo "   ✅ PASSED: Got '$result' seconds"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "🔹 TEST $((TOTAL_TESTS + 1)): TTL_CHECK"
    echo "   Command: TTL ttltest"
    echo "   Expected: 25-30 seconds"
    echo "   Description: TTL should return remaining seconds"
    echo "   ❌ FAILED: Got '$result' seconds"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

echo "🔄 **EXPIRE COMMAND TESTS**"
echo "---------------------------"

# Set key without expiry, then add expiry
run_test "SET_NO_EXPIRY" "SET expiretest expirevalue" "OK" "Set key without expiry"
run_test "EXPIRE_SET" "EXPIRE expiretest 45" "1" "Set expiry on existing key"

# Check TTL after EXPIRE
sleep 1
result=$(redis-cli -h $HOST -p $PORT -c "TTL expiretest" 2>&1)
if [[ "$result" -ge 40 && "$result" -le 45 ]]; then
    echo "🔹 TEST $((TOTAL_TESTS + 1)): TTL_AFTER_EXPIRE"
    echo "   Command: TTL expiretest (after EXPIRE)"
    echo "   Expected: 40-45 seconds"
    echo "   Description: TTL should work after EXPIRE command"
    echo "   ✅ PASSED: Got '$result' seconds"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "🔹 TEST $((TOTAL_TESTS + 1)): TTL_AFTER_EXPIRE"
    echo "   Command: TTL expiretest (after EXPIRE)"
    echo "   Expected: 40-45 seconds"
    echo "   Description: TTL should work after EXPIRE command"
    echo "   ❌ FAILED: Got '$result' seconds"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

# EXPIRE on non-existent key
run_test "EXPIRE_MISSING" "EXPIRE nonexistent 60" "0" "EXPIRE on non-existent key should return 0"

echo "❓ **TTL EDGE CASES**"
echo "--------------------"

# TTL on non-existent key
run_test "TTL_MISSING" "TTL nonexistent" "-2" "TTL on non-existent key should return -2"

# TTL on key without expiry
run_command "SET noexpiry somevalue"
run_test "TTL_NO_EXPIRY" "TTL noexpiry" "-1" "TTL on key without expiry should return -1"

echo "🔢 **NUMERIC VALUES**"
echo "---------------------"

# Test with numeric values
run_test "SET_NUMBER" "SET numkey 12345" "OK" "Set numeric value"
run_test "GET_NUMBER" "GET numkey" "12345" "Get numeric value back"

echo "📏 **LARGE VALUES**"
echo "-------------------"

# Test with larger value
large_value=$(printf 'A%.0s' {1..1000})  # 1000 A's
run_test "SET_LARGE" "SET largekey $large_value" "OK" "Set large value (1000 chars)"
result=$(redis-cli -h $HOST -p $PORT -c "GET largekey" 2>&1)
if [ ${#result} -eq 1000 ]; then
    echo "🔹 TEST $((TOTAL_TESTS + 1)): GET_LARGE"
    echo "   Command: GET largekey"
    echo "   Expected: 1000 character string"
    echo "   Description: Get large value back"
    echo "   ✅ PASSED: Got string of length ${#result}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "🔹 TEST $((TOTAL_TESTS + 1)): GET_LARGE"
    echo "   Command: GET largekey"
    echo "   Expected: 1000 character string"
    echo "   Description: Get large value back"
    echo "   ❌ FAILED: Got string of length ${#result}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo ""

echo "🔗 **MULTIPLE OPERATIONS**"
echo "--------------------------"

# Multiple operations in sequence
run_test "MULTI_SET_1" "SET key1 value1" "OK" "Set first key"
run_test "MULTI_SET_2" "SET key2 value2" "OK" "Set second key"
run_test "MULTI_SET_3" "SET key3 value3" "OK" "Set third key"

run_test "MULTI_GET_1" "GET key1" "value1" "Get first key"
run_test "MULTI_GET_2" "GET key2" "value2" "Get second key"
run_test "MULTI_GET_3" "GET key3" "value3" "Get third key"

echo "🧹 **CLEANUP TESTS**"
echo "--------------------"

run_test "CLEANUP_DEL_1" "DEL key1" "1" "Delete first key"
run_test "CLEANUP_DEL_2" "DEL key2" "1" "Delete second key"
run_test "CLEANUP_DEL_3" "DEL key3" "1" "Delete third key"

echo "📊 **TEST SUMMARY**"
echo "==================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "Success Rate: $(( TESTS_PASSED * 100 / TOTAL_TESTS ))%"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "🎉 **ALL TESTS PASSED!** Meteor server is fully Redis-compatible!"
    exit 0
else
    echo "⚠️  **$TESTS_FAILED TESTS FAILED** - Redis compatibility issues detected"
    exit 1
fi
