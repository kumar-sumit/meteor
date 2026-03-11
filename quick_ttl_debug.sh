#!/bin/bash

echo "🔍 QUICK TTL DEBUG - Run this on VM to identify the failed test"
echo "============================================================="
echo ""

# Check if server is running
if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "✅ Server is responding"
else
    echo "❌ Server not responding - start it first:"
    echo "   ./meteor_commercial_lru_ttl_final -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &"
    exit 1
fi

echo ""
echo "🧪 DEBUGGING EACH TTL TEST CASE:"
echo "================================"

# Clear any existing data
redis-cli -p 6379 flushall >/dev/null 2>&1

# Test 1: Key without TTL should return -1
echo ""
echo "🔎 TEST 1: Key without TTL"
echo "   Command: SET no_ttl_key 'permanent'"
redis-cli -p 6379 set no_ttl_key "permanent" >/dev/null
echo "   Verify key exists:"
GET_RESULT=$(redis-cli -p 6379 get no_ttl_key 2>/dev/null)
echo "   GET no_ttl_key -> '$GET_RESULT'"

if [ "$GET_RESULT" = "permanent" ]; then
    echo "   ✅ Key stored correctly"
    
    echo "   Testing TTL:"
    TTL_RESULT=$(redis-cli -p 6379 ttl no_ttl_key 2>/dev/null)
    echo "   TTL no_ttl_key -> $TTL_RESULT"
    
    if [ "$TTL_RESULT" = "-1" ]; then
        echo "   ✅ TEST 1 PASSED"
    else
        echo "   ❌ TEST 1 FAILED - Expected -1, got $TTL_RESULT"
        echo "   🐛 ISSUE: Key without TTL returning wrong value"
    fi
else
    echo "   ❌ Key not stored properly - SET command failed"
    echo "   🐛 ISSUE: SET method not working"
fi

echo ""
echo "🔎 TEST 2: Non-existent key"
TTL_NONEXIST=$(redis-cli -p 6379 ttl totally_nonexistent_key_xyz 2>/dev/null)
echo "   Command: TTL totally_nonexistent_key_xyz"
echo "   Result: $TTL_NONEXIST"

if [ "$TTL_NONEXIST" = "-2" ]; then
    echo "   ✅ TEST 2 PASSED"
else
    echo "   ❌ TEST 2 FAILED - Expected -2, got $TTL_NONEXIST"
    echo "   🐛 ISSUE: Non-existent key TTL logic error"
fi

echo ""
echo "🔎 TEST 3: Key with TTL"
echo "   Command: SET ttl_key 'expires' EX 45"
redis-cli -p 6379 set ttl_key "expires" EX 45 >/dev/null
echo "   Verify key exists:"
GET_TTL_KEY=$(redis-cli -p 6379 get ttl_key 2>/dev/null)
echo "   GET ttl_key -> '$GET_TTL_KEY'"

if [ "$GET_TTL_KEY" = "expires" ]; then
    echo "   ✅ Key with TTL stored correctly"
    
    echo "   Testing TTL:"
    TTL_WITH_EX=$(redis-cli -p 6379 ttl ttl_key 2>/dev/null)
    echo "   TTL ttl_key -> $TTL_WITH_EX"
    
    if [ "$TTL_WITH_EX" -gt 0 ] && [ "$TTL_WITH_EX" -le 45 ]; then
        echo "   ✅ TEST 3 PASSED"
    else
        echo "   ❌ TEST 3 FAILED - Expected >0 and <=45, got $TTL_WITH_EX"
        echo "   🐛 ISSUE: SET EX command not setting TTL properly"
    fi
else
    echo "   ❌ Key with TTL not stored properly"
    echo "   🐛 ISSUE: SET EX command failed"
fi

echo ""
echo "🔎 TEST 4: EXPIRE command"
echo "   Command: SET expire_test 'gets ttl later'"
redis-cli -p 6379 set expire_test "gets ttl later" >/dev/null
echo "   Verify key exists:"
GET_EXPIRE_KEY=$(redis-cli -p 6379 get expire_test 2>/dev/null)
echo "   GET expire_test -> '$GET_EXPIRE_KEY'"

if [ "$GET_EXPIRE_KEY" = "gets ttl later" ]; then
    echo "   ✅ Key for EXPIRE test stored correctly"
    
    echo "   Command: EXPIRE expire_test 40"
    EXPIRE_RESULT=$(redis-cli -p 6379 expire expire_test 40 2>/dev/null)
    echo "   EXPIRE result -> $EXPIRE_RESULT (should be 1)"
    
    if [ "$EXPIRE_RESULT" = "1" ]; then
        echo "   ✅ EXPIRE command succeeded"
        
        echo "   Testing TTL after EXPIRE:"
        TTL_AFTER_EXPIRE=$(redis-cli -p 6379 ttl expire_test 2>/dev/null)
        echo "   TTL expire_test -> $TTL_AFTER_EXPIRE"
        
        if [ "$TTL_AFTER_EXPIRE" -gt 0 ] && [ "$TTL_AFTER_EXPIRE" -le 40 ]; then
            echo "   ✅ TEST 4 PASSED"
        else
            echo "   ❌ TEST 4 FAILED - Expected >0 and <=40, got $TTL_AFTER_EXPIRE"
            echo "   🐛 ISSUE: EXPIRE command not setting TTL correctly"
        fi
    else
        echo "   ❌ EXPIRE command failed - Expected 1, got $EXPIRE_RESULT"
        echo "   🐛 ISSUE: EXPIRE command implementation problem"
    fi
else
    echo "   ❌ Key for EXPIRE test not stored"
    echo "   🐛 ISSUE: SET command failed"
fi

echo ""
echo "🔍 ADDITIONAL DEBUG INFO:"
echo "========================"

# Check if server has any specific errors
echo "Server info:"
redis-cli -p 6379 info server 2>/dev/null | grep -E "redis_version|uptime|tcp_port" | head -3

echo ""
echo "Memory info:"
redis-cli -p 6379 info memory 2>/dev/null | grep -E "used_memory|used_memory_human" | head -2

echo ""
echo "Keyspace info:"
redis-cli -p 6379 info keyspace 2>/dev/null

echo ""
echo "📋 DEBUG COMPLETE"
echo "=================="
echo ""
echo "Based on the results above, identify which test failed and:"
echo "1. Share the specific error with the development team"
echo "2. Check the TTL_TEST_FAILURE_DIAGNOSIS.md file for solutions"
echo "3. Apply the appropriate fix based on the failing test case"
echo ""













