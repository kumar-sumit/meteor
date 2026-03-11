# 🔧 **KEY ROUTING CONSISTENCY FIX - MANUAL TEST**

## 🎯 **THE EXACT ISSUE FOUND & FIXED**

**ROOT CAUSE**: TTL and EXPIRE commands were NOT included in key routing logic!

```cpp
// BEFORE (BROKEN) - line 3401:
if ((cmd_upper == "GET" || cmd_upper == "SET" || cmd_upper == "DEL") && !key.empty()) {
    // Route to correct core based on key hash
}
// TTL and EXPIRE commands were NOT routed!

// AFTER (FIXED):
if ((cmd_upper == "GET" || cmd_upper == "SET" || cmd_upper == "DEL" || 
     cmd_upper == "TTL" || cmd_upper == "EXPIRE") && !key.empty()) {
    // Now TTL/EXPIRE route to same core as SET!
}
```

**RESULT**: SET and TTL now use **consistent key hashing** → same core → consistent results!

---

## 🧪 **MANUAL TEST COMMANDS**

### **STEP 1: SSH to VM and Build**
```bash
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>"

cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 3

# Build routing-consistent version
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_routing_consistent meteor_commercial_lru_ttl_routing_consistent.cpp -luring
```

### **STEP 2: Start Multi-Core Server**
```bash
./meteor_routing_consistent -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &
SERVER_PID=$!
sleep 5
redis-cli -p 6379 ping
```

### **STEP 3: CRITICAL TEST - Routing Consistency**
```bash
redis-cli -p 6379 flushall

echo "🎯 Testing routing consistency (was random -2/-1 before fix)"

# Test 10 keys to verify consistent routing
for i in {1..10}; do
    KEY="routing_test_key_$i"
    
    # Set key (routes to some core)
    redis-cli -p 6379 set "$KEY" "value_$i"
    
    # TTL should route to SAME core (consistent result)
    TTL_RESULT=$(redis-cli -p 6379 ttl "$KEY")
    echo "Key $i: TTL -> $TTL_RESULT (should always be -1)"
done

echo ""
echo "✅ SUCCESS: All results should be -1 (no random -2 results)"
echo "❌ FAILURE: If you still see -2 results, routing fix incomplete"
```

### **STEP 4: Test TTL Logic Correctness**
```bash
echo ""
echo "🧪 Testing TTL logic correctness with consistent routing"

# Test 1: Key without TTL (should ALWAYS be -1)
redis-cli -p 6379 set logic_test_1 "no ttl"
redis-cli -p 6379 ttl logic_test_1
echo "Expected: -1 (consistently)"

# Test 2: Key with TTL (should ALWAYS be >0)
redis-cli -p 6379 set logic_test_2 "has ttl" EX 60
redis-cli -p 6379 ttl logic_test_2
echo "Expected: >0 and ≤60 (consistently)"

# Test 3: EXPIRE command (should ALWAYS work)
redis-cli -p 6379 set logic_test_3 "gets expire"
redis-cli -p 6379 expire logic_test_3 45
redis-cli -p 6379 ttl logic_test_3
echo "Expected: 1, then >0 and ≤45 (consistently)"

# Test 4: Non-existent key (should ALWAYS be -2)
redis-cli -p 6379 ttl totally_nonexistent_key
echo "Expected: -2 (consistently)"
```

### **STEP 5: Repeated Consistency Test**
```bash
echo ""
echo "🔄 Testing consistency with repeated calls"

# This should give SAME result every time (no random variation)
for i in {1..5}; do
    redis-cli -p 6379 ttl logic_test_1  # Should always be -1
    redis-cli -p 6379 ttl logic_test_2  # Should always be >0
done

echo ""
echo "✅ SUCCESS: Same results every time"
echo "❌ FAILURE: If results vary randomly, routing still inconsistent"
```

### **STEP 6: Performance Verification**
```bash
echo ""
echo "🏃 Performance test (should maintain 5M+ QPS)"

memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
  --clients=50 --threads=12 --pipeline=10 --data-size=64 \
  --key-pattern=R:R --ratio=1:3 --test-time=30

echo ""
echo "Look for 'Requests/sec' - should be 5,000,000+"
```

### **STEP 7: Cleanup**
```bash
kill $SERVER_PID 2>/dev/null
```

---

## 🎯 **SUCCESS CRITERIA**

### **✅ ROUTING FIX SUCCESS**:
- **All TTL commands return -1** for keys without TTL (no random -2 results)
- **All TTL commands return >0** for keys with TTL (no random -2 results)
- **Consistent results** across multiple calls to same key
- **5M+ QPS** performance maintained

### **❌ ROUTING FIX FAILED**:
- **Still getting random -2/-1** results for same key
- **TTL commands still inconsistent** across multiple calls
- **Performance regression** below 1M QPS

### **⚠️ PARTIAL SUCCESS**:
- **Most keys consistent** but some still random
- **Generally improved** but occasional inconsistencies

---

## 🔍 **WHAT TO OBSERVE**

### **BEFORE FIX** (what you experienced):
```bash
redis-cli -p 6379 set test_key "value"
redis-cli -p 6379 ttl test_key    # Sometimes -1, sometimes -2 (random!)
redis-cli -p 6379 ttl test_key    # Different result each time
```

### **AFTER FIX** (what you should see):
```bash
redis-cli -p 6379 set test_key "value"
redis-cli -p 6379 ttl test_key    # Always -1
redis-cli -p 6379 ttl test_key    # Always -1 (consistent!)
```

---

## 🚨 **IF STILL FAILING**

### **Debug Commands**:
```bash
# Test with single core (eliminates routing)
pkill -f meteor
./meteor_routing_consistent -h 127.0.0.1 -p 6379 -c 1 -s 1 -m 512 &

# Should be consistent with single core
redis-cli -p 6379 set debug_key "value"
redis-cli -p 6379 ttl debug_key    # Should always be -1
```

### **Additional Issues to Check**:
1. **Thread-local storage** routing inconsistencies
2. **Hash function** differences between commands  
3. **Core assignment** logic problems

---

## 🏆 **EXPECTED OUTCOME**

**With this routing fix, your TTL commands should now be 100% consistent:**
- ✅ **No more random -2/-1** results
- ✅ **TTL always routes to correct core**
- ✅ **All key-based commands use same hashing**
- ✅ **Performance maintained**

**Test with the commands above and report if you still see inconsistent results!** 🎯













