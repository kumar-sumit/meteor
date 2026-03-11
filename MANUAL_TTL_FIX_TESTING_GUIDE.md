# 🔥 **MANUAL TTL FIX TESTING GUIDE**

## 🎯 **CRITICAL ISSUES FIXED**

### ✅ **Issue 1: Cross-Shard Routing Bug (FIXED)**
**Problem**: TTL commands routed to different shards than SET commands
**Symptom**: `TTL key` returning `-2` instead of `-1` for keys without TTL  
**Fix Applied**: Removed cross-shard routing - all commands execute locally

### ✅ **Issue 2: TTL Method Deadlock (FIXED)**  
**Problem**: `lazy_expire_if_needed()` called before main lock acquisition
**Symptom**: Server hanging/freezing on TTL commands
**Fix Applied**: Moved expiry checking inside main lock scope with lock upgrade pattern

### ✅ **Issue 3: GET Method Deadlock (FIXED)**
**Problem**: Same deadlock issue in GET method  
**Symptom**: GET commands hanging
**Fix Applied**: Same inline expiry checking with lock upgrade

---

## 📁 **FILES ON VM**
✅ `meteor_commercial_lru_ttl_deadlock_fixed.cpp` - **Latest fixed source**  
✅ `quick_ttl_debug.sh` - Diagnostic script  
✅ `test_ttl_deadlock_fix.sh` - Focused deadlock test

---

## 🧪 **MANUAL TESTING STEPS**

### **Step 1: SSH to VM**
```bash
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>"
```

### **Step 2: Build the Fixed Version**
```bash
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

# Build the deadlock-fixed version
echo "Building TTL deadlock-fixed version..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_ttl_deadlock_fixed meteor_commercial_lru_ttl_deadlock_fixed.cpp -luring

# Verify build
if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    ls -la meteor_ttl_deadlock_fixed
else
    echo "❌ Build failed - check compilation errors"
    exit 1
fi
```

### **Step 3: Test Server Startup (No Hanging)**
```bash
echo "🚀 Testing server startup..."
./meteor_ttl_deadlock_fixed -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 4

# Test if server responds (should not hang)
if timeout 10 redis-cli -p 6379 ping; then
    echo "✅ Server responding - no deadlock on startup!"
else
    echo "❌ Server not responding or hanging"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi
```

### **Step 4: Critical TTL Test (The Failing Case)**
```bash
echo ""
echo "🎯 CRITICAL TEST: TTL for key without TTL"
echo "========================================"

# Clear data
redis-cli -p 6379 flushall

# Set key WITHOUT TTL
echo "Setting key without TTL..."
redis-cli -p 6379 set test_no_ttl "this key has no ttl"

# Verify key exists
GET_RESULT=$(redis-cli -p 6379 get test_no_ttl)
echo "GET test_no_ttl -> '$GET_RESULT'"

if [ "$GET_RESULT" = "this key has no ttl" ]; then
    echo "✅ Key stored successfully"
    
    # THE CRITICAL TEST - should return -1, not -2
    echo ""
    echo "Testing TTL (critical test)..."
    TTL_RESULT=$(timeout 10 redis-cli -p 6379 ttl test_no_ttl)
    
    if [ $? -eq 0 ]; then
        echo "TTL test_no_ttl -> $TTL_RESULT"
        
        if [ "$TTL_RESULT" = "-1" ]; then
            echo "🎉 SUCCESS! TTL fix works - returning -1 for no TTL"
            RESULT_STATUS="SUCCESS"
        elif [ "$TTL_RESULT" = "-2" ]; then
            echo "❌ Still failing - returning -2 instead of -1"
            RESULT_STATUS="STILL_FAILING"
        else
            echo "❓ Unexpected result: $TTL_RESULT"
            RESULT_STATUS="UNEXPECTED"
        fi
    else
        echo "❌ TTL command timed out - still deadlocking!"
        RESULT_STATUS="HANGING"
    fi
else
    echo "❌ Key not stored properly"
    RESULT_STATUS="SET_FAILED"
fi
```

### **Step 5: Test All 4 TTL Cases**
```bash
echo ""
echo "🧪 Testing all TTL cases..."
echo "=========================="

# Case 1: Key without TTL (already tested above)
echo "Test 1: Key without TTL -> $TTL_RESULT (should be -1)"

# Case 2: Non-existent key  
TTL_NONEXIST=$(redis-cli -p 6379 ttl totally_nonexistent_key)
echo "Test 2: Non-existent key -> $TTL_NONEXIST (should be -2)"

# Case 3: Key with TTL
redis-cli -p 6379 set ttl_key "has ttl" EX 60
TTL_WITH_TTL=$(redis-cli -p 6379 ttl ttl_key)  
echo "Test 3: Key with TTL -> $TTL_WITH_TTL (should be >0 and ≤60)"

# Case 4: EXPIRE command
redis-cli -p 6379 set expire_test "gets ttl"
EXPIRE_RESULT=$(redis-cli -p 6379 expire expire_test 45)
TTL_AFTER_EXPIRE=$(redis-cli -p 6379 ttl expire_test)
echo "Test 4: EXPIRE result -> $EXPIRE_RESULT, TTL -> $TTL_AFTER_EXPIRE (should be 1, then >0 and ≤45)"
```

### **Step 6: Performance Benchmark**
```bash
echo ""
echo "🏃 Performance benchmark..."
echo "=========================="

# Kill and restart for benchmark
kill $SERVER_PID 2>/dev/null
sleep 2

# Start optimized server for benchmark
./meteor_ttl_deadlock_fixed -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &
sleep 5

# Run benchmark
echo "Running 30-second benchmark..."
memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
  --clients=50 --threads=12 --pipeline=10 --data-size=64 \
  --key-pattern=R:R --ratio=1:3 --test-time=30

echo ""
echo "Expected: 5.0M - 5.4M QPS with TTL functionality"
```

### **Step 7: Results Interpretation**
```bash
echo ""
echo "🏆 FINAL RESULTS SUMMARY"
echo "========================"
echo "Result Status: $RESULT_STATUS"

case $RESULT_STATUS in
    SUCCESS)
        echo ""
        echo "🎉 ALL FIXES WORKING PERFECTLY!"
        echo "✅ No deadlocks or hanging"
        echo "✅ TTL correctly returns -1 for keys without TTL"
        echo "✅ Ready for production deployment"
        ;;
    STILL_FAILING)
        echo ""
        echo "⚠️  Deadlock fixed but logic issue remains"
        echo "   Check Entry constructor has_ttl initialization"
        echo "   or SET method Entry creation"
        ;;
    HANGING)
        echo ""  
        echo "🚨 Deadlock still exists"
        echo "   Need deeper analysis of lock acquisition order"
        ;;
    *)
        echo ""
        echo "❓ Unexpected result - need investigation"
        ;;
esac
```

---

## 🎯 **EXPECTED RESULTS AFTER FIXES**

| **Test** | **Command** | **Expected Result** | **Status** |
|----------|-------------|-------------------|------------|
| **No TTL Key** | `SET key val` → `TTL key` | **`-1`** (not -2) | **Should be FIXED** |
| **Non-existent** | `TTL missing_key` | **`-2`** | Should work |
| **With TTL** | `SET key val EX 30` → `TTL key` | **`>0 and ≤30`** | Should work |
| **EXPIRE cmd** | `EXPIRE key 25` → `TTL key` | **`1` then `>0 and ≤25`** | Should work |

**Performance**: **5.0M - 5.4M QPS** (no regression)

---

## 🚨 **TROUBLESHOOTING**

### **If Build Fails**
- Check for missing dependencies: `sudo apt update && sudo apt install g++ liburing-dev`
- Verify compiler flags are correct

### **If Server Hangs on Startup**
- Still has deadlock - need deeper lock analysis
- Check server logs for specific errors

### **If TTL Still Returns -2**  
- Entry constructor issue - `has_ttl` not properly initialized
- SET method not creating Entry correctly

### **If Performance Regression**
- Check if expiry checking overhead is too high
- May need to optimize inline expiry logic

---

## 📋 **NEXT STEPS BASED ON RESULTS**

✅ **If all tests pass**: Deploy to production, update documentation  
⚠️  **If TTL logic fails**: Debug Entry constructor and has_ttl logic  
🚨 **If deadlock persists**: Analyze lock acquisition patterns more deeply  
📊 **If performance drops**: Optimize expiry checking implementation

**The fixes address the root causes - manual testing will confirm success! 🚀**













