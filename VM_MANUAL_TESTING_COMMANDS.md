# 🧪 **VM MANUAL TESTING COMMANDS - REDIS-STYLE TTL**

## **STEP 1: SSH TO VM**
```bash
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>"
```

---

## **STEP 2: BUILD REDIS-STYLE VERSION**
```bash
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm

# Kill any existing meteor server
pkill -f meteor 2>/dev/null || true
sleep 3

# Build the Redis-style version
echo "🚀 Building Redis-style TTL implementation..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_redis_style meteor_commercial_lru_ttl_redis_style.cpp -luring

# Check build status
if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    ls -la meteor_redis_style
else
    echo "❌ Build failed - check compiler errors"
    exit 1
fi
```

---

## **STEP 3: START SERVER AND TEST CONNECTIVITY**
```bash
echo ""
echo "🚀 Starting Redis-style server..."
./meteor_redis_style -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 5

# Test basic connectivity
echo "Testing server connectivity..."
if timeout 10 redis-cli -p 6379 ping; then
    echo "✅ Server responding!"
else
    echo "❌ Server not responding - check for startup issues"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi
```

---

## **STEP 4: CRITICAL TTL TESTS**

### **Test 4.1: TTL Response Time (Should be <100ms, not hanging)**
```bash
echo ""
echo "🎯 CRITICAL TEST: TTL response time"
echo "==================================="

# Clear any existing data
redis-cli -p 6379 flushall

# Set key without TTL
echo "Setting key without TTL..."
redis-cli -p 6379 set ttl_speed_test "no ttl value"

# Verify key exists
GET_CHECK=$(redis-cli -p 6379 get ttl_speed_test)
echo "GET ttl_speed_test -> '$GET_CHECK'"

if [ "$GET_CHECK" = "no ttl value" ]; then
    echo "✅ Key stored successfully"
    
    # Measure TTL response time
    echo "Measuring TTL response time..."
    START_TIME=$(date +%s%N)
    TTL_RESULT=$(timeout 10 redis-cli -p 6379 ttl ttl_speed_test)
    EXIT_CODE=$?
    END_TIME=$(date +%s%N)
    DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
    
    echo "TTL execution time: ${DURATION_MS}ms"
    echo "TTL ttl_speed_test -> $TTL_RESULT"
    
    if [ $EXIT_CODE -eq 0 ] && [ $DURATION_MS -lt 100 ]; then
        if [ "$TTL_RESULT" = "-1" ]; then
            echo "🎉 SUCCESS! TTL working perfectly!"
            echo "✅ Fast response time (${DURATION_MS}ms)"
            echo "✅ Correct logic (-1 for keys without TTL)"
        elif [ "$TTL_RESULT" = "-2" ]; then
            echo "⚠️  Fast response but logic issue"
            echo "✅ Performance fixed (${DURATION_MS}ms)"
            echo "❌ Still returning -2 instead of -1"
        else
            echo "❓ Unexpected result: $TTL_RESULT"
        fi
    else
        echo "❌ TTL still hanging or timing out!"
    fi
else
    echo "❌ Key not stored properly"
fi
```

### **Test 4.2: All TTL Logic Cases**
```bash
echo ""
echo "🧪 TTL LOGIC CORRECTNESS TEST"
echo "============================"

# Clear data
redis-cli -p 6379 flushall

echo "Test 1: Key without TTL (should return -1)"
redis-cli -p 6379 set test1 "no ttl"
TTL1=$(redis-cli -p 6379 ttl test1)
echo "TTL test1 -> $TTL1 (expected: -1)"

echo ""
echo "Test 2: Non-existent key (should return -2)"
TTL2=$(redis-cli -p 6379 ttl nonexistent_key_xyz)
echo "TTL nonexistent_key_xyz -> $TTL2 (expected: -2)"

echo ""
echo "Test 3: Key with TTL (should return >0)"
redis-cli -p 6379 set test3 "has ttl" EX 60
TTL3=$(redis-cli -p 6379 ttl test3)
echo "TTL test3 (EX 60) -> $TTL3 (expected: >0 and ≤60)"

echo ""
echo "Test 4: EXPIRE command (should work)"
redis-cli -p 6379 set test4 "gets expire"
EXPIRE_RESULT=$(redis-cli -p 6379 expire test4 45)
TTL4=$(redis-cli -p 6379 ttl test4)
echo "EXPIRE test4 45 -> $EXPIRE_RESULT (expected: 1)"
echo "TTL test4 -> $TTL4 (expected: >0 and ≤45)"

# Evaluate results
echo ""
echo "📊 TEST RESULTS SUMMARY:"
echo "Test 1 (no TTL): $TTL1 (should be -1)"
echo "Test 2 (non-existent): $TTL2 (should be -2)"
echo "Test 3 (with TTL): $TTL3 (should be >0)"
echo "Test 4 (EXPIRE): $EXPIRE_RESULT, TTL: $TTL4 (should be 1, >0)"
```

### **Test 4.3: Stress Test (No Hanging Under Load)**
```bash
echo ""
echo "🚀 STRESS TEST: Concurrent TTL operations"
echo "========================================"

echo "Running 100 concurrent TTL commands..."
START_TIME=$(date +%s)

# Run concurrent TTL operations
{
    for i in {1..25}; do redis-cli -p 6379 ttl test1 >/dev/null & done
    for i in {1..25}; do redis-cli -p 6379 ttl test3 >/dev/null & done
    for i in {1..25}; do redis-cli -p 6379 get test1 >/dev/null & done
    for i in {1..25}; do redis-cli -p 6379 get test3 >/dev/null & done
    wait
}

END_TIME=$(date +%s)
STRESS_DURATION=$((END_TIME - START_TIME))

echo "Stress test completed in ${STRESS_DURATION} seconds"

if [ $STRESS_DURATION -lt 10 ]; then
    echo "✅ Stress test passed - no hanging under concurrent load"
else
    echo "❌ Stress test slow - possible deadlock issues remain"
fi
```

---

## **STEP 5: PERFORMANCE BENCHMARK**

### **Test 5.1: Full Performance Test (Should maintain 5M+ QPS)**
```bash
echo ""
echo "🏃 PERFORMANCE BENCHMARK - NO REGRESSION TEST"
echo "============================================="

echo "Running 30-second performance benchmark..."
echo "Expected: 5.0M - 5.4M QPS (Phase 1.2B baseline)"

memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
  --clients=50 --threads=12 --pipeline=10 --data-size=64 \
  --key-pattern=R:R --ratio=1:3 --test-time=30

echo ""
echo "📊 PERFORMANCE ANALYSIS:"
echo "- Look for 'Totals' section"
echo "- Check 'Requests/sec' value"
echo "- Verify p50/p95/p99 latencies are reasonable"
echo "- Should see 5M+ requests/sec for SUCCESS"
```

### **Test 5.2: TTL-Specific Performance**
```bash
echo ""
echo "🧪 TTL-SPECIFIC PERFORMANCE TEST"
echo "==============================="

echo "Testing TTL performance impact..."

# Set up test data with mixed TTL/no-TTL keys
redis-cli -p 6379 flushall
for i in {1..100}; do
    redis-cli -p 6379 set "no_ttl_key_$i" "value_$i" >/dev/null
    redis-cli -p 6379 set "ttl_key_$i" "value_$i" EX 3600 >/dev/null
done

echo "Created 100 keys without TTL and 100 keys with TTL"

# Test TTL performance on mixed dataset
echo "Running TTL performance test..."
START_TIME=$(date +%s%N)

for i in {1..100}; do
    redis-cli -p 6379 ttl "no_ttl_key_$i" >/dev/null
    redis-cli -p 6379 ttl "ttl_key_$i" >/dev/null
done

END_TIME=$(date +%s%N)
TOTAL_MS=$(( (END_TIME - START_TIME) / 1000000 ))
AVG_MS=$(( TOTAL_MS / 200 ))

echo "200 TTL operations completed in ${TOTAL_MS}ms"
echo "Average TTL response time: ${AVG_MS}ms"

if [ $AVG_MS -lt 10 ]; then
    echo "✅ Excellent TTL performance (${AVG_MS}ms avg)"
elif [ $AVG_MS -lt 50 ]; then
    echo "✅ Good TTL performance (${AVG_MS}ms avg)"
else
    echo "⚠️  TTL performance needs improvement (${AVG_MS}ms avg)"
fi
```

---

## **STEP 6: FINAL VALIDATION**

### **Test 6.1: Edge Cases**
```bash
echo ""
echo "🔍 EDGE CASE TESTING"
echo "==================="

# Test SET EX with various TTL values
echo "Testing SET EX with different TTL values..."
redis-cli -p 6379 set edge1 "1sec" EX 1
redis-cli -p 6379 set edge2 "1hour" EX 3600
redis-cli -p 6379 set edge3 "1day" EX 86400

TTL_EDGE1=$(redis-cli -p 6379 ttl edge1)
TTL_EDGE2=$(redis-cli -p 6379 ttl edge2)
TTL_EDGE3=$(redis-cli -p 6379 ttl edge3)

echo "TTL edge1 (1sec): $TTL_EDGE1"
echo "TTL edge2 (1hour): $TTL_EDGE2"
echo "TTL edge3 (1day): $TTL_EDGE3"

# Test EXPIRE on keys without TTL
echo ""
echo "Testing EXPIRE on key without TTL..."
redis-cli -p 6379 set expire_test "no initial ttl"
EXPIRE_NO_TTL=$(redis-cli -p 6379 expire expire_test 120)
TTL_AFTER_EXPIRE=$(redis-cli -p 6379 ttl expire_test)
echo "EXPIRE expire_test 120 -> $EXPIRE_NO_TTL (expected: 1)"
echo "TTL expire_test -> $TTL_AFTER_EXPIRE (expected: >0 and ≤120)"
```

### **Test 6.2: Server Stability**
```bash
echo ""
echo "🔒 SERVER STABILITY TEST"
echo "======================="

echo "Testing server stability over time..."
sleep 10

# Check if server is still responding after all tests
if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "✅ Server stable after all tests"
    
    # Check memory usage
    MEMORY_INFO=$(redis-cli -p 6379 info memory 2>/dev/null | grep used_memory_human)
    echo "Memory usage: $MEMORY_INFO"
    
    # Check keyspace
    KEYSPACE_INFO=$(redis-cli -p 6379 info keyspace 2>/dev/null)
    echo "Keyspace: $KEYSPACE_INFO"
else
    echo "❌ Server became unresponsive during testing"
fi
```

---

## **STEP 7: CLEANUP AND RESULTS**
```bash
echo ""
echo "🧹 CLEANUP"
echo "=========="

# Kill server
kill $SERVER_PID 2>/dev/null || true
echo "Server stopped"

echo ""
echo "🏆 REDIS-STYLE TTL TEST COMPLETE"
echo "==============================="

echo ""
echo "📋 EXPECTED SUCCESS CRITERIA:"
echo "✅ TTL commands respond in <100ms (no hanging)"
echo "✅ TTL returns -1 for keys without TTL (not -2)"
echo "✅ TTL returns -2 for non-existent keys"
echo "✅ TTL returns >0 for keys with TTL"
echo "✅ EXPIRE command works correctly"
echo "✅ 5M+ QPS in benchmark (no performance regression)"
echo "✅ Server stable under concurrent load"

echo ""
echo "📊 REPORT YOUR RESULTS:"
echo "1. TTL response times (should be <100ms)"
echo "2. TTL logic correctness (test1-4 results)"
echo "3. Benchmark QPS (should be 5M+)"
echo "4. Any hanging or timeout issues"

echo ""
echo "🎯 If all tests pass: REDIS-STYLE SOLUTION IS WORKING!"
echo "🎯 If still hanging: Need deeper architecture review"
echo "🎯 If logic issues: Need Entry constructor debugging"
```

---

## **COPY-PASTE COMMAND BLOCKS**

### **Block 1: SSH and Build**
```bash
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>"

cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 3

g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_redis_style meteor_commercial_lru_ttl_redis_style.cpp -luring

ls -la meteor_redis_style
```

### **Block 2: Start Server and Basic Test**
```bash
./meteor_redis_style -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &
SERVER_PID=$!
sleep 5
redis-cli -p 6379 ping
```

### **Block 3: TTL Logic Tests**
```bash
redis-cli -p 6379 flushall

redis-cli -p 6379 set test1 "no ttl"
redis-cli -p 6379 ttl test1
# Expected: -1

redis-cli -p 6379 ttl nonexistent_key
# Expected: -2

redis-cli -p 6379 set test3 "has ttl" EX 60
redis-cli -p 6379 ttl test3
# Expected: >0 and ≤60

redis-cli -p 6379 set test4 "gets expire"
redis-cli -p 6379 expire test4 45
redis-cli -p 6379 ttl test4
# Expected: 1, then >0 and ≤45
```

### **Block 4: Performance Benchmark**
```bash
memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
  --clients=50 --threads=12 --pipeline=10 --data-size=64 \
  --key-pattern=R:R --ratio=1:3 --test-time=30
```

### **Block 5: Cleanup**
```bash
kill $SERVER_PID 2>/dev/null
```

---

## **QUICK SUCCESS/FAILURE INDICATORS**

### **✅ SUCCESS INDICATORS:**
- TTL commands return results in <100ms
- TTL returns `-1` for keys without TTL
- Benchmark shows 5M+ QPS
- No timeout or hanging messages

### **❌ FAILURE INDICATORS:**
- TTL commands hang or timeout
- TTL returns `-2` instead of `-1`
- Benchmark shows <1M QPS
- Server becomes unresponsive

### **⚠️ PARTIAL SUCCESS:**
- TTL fast but wrong logic (-2 vs -1)
- Performance good but occasional hangs
- Most tests pass but some edge cases fail

---

## **DEBUGGING IF ISSUES PERSIST**

### **If TTL Still Hangs:**
```bash
# Check server logs
tail -50 /var/log/syslog | grep meteor

# Check process status
ps aux | grep meteor

# Test with single core (simpler config)
pkill -f meteor
./meteor_redis_style -h 127.0.0.1 -p 6379 -c 1 -s 1 -m 512 &
```

### **If Logic Issues Persist:**
```bash
# Add debug prints to check has_ttl values
redis-cli -p 6379 set debug_key "test"
redis-cli -p 6379 get debug_key    # Should work
redis-cli -p 6379 ttl debug_key    # Check result
```

---

**COPY THESE COMMANDS TO VM AND RUN SEQUENTIALLY!** 🚀













