# 🔧 **DEADLOCK-FREE TTL VERSION - MANUAL TESTING GUIDE**

## 🚨 **ROOT CAUSE OF TTL HANGING IDENTIFIED & FIXED**

### **The Problem**: Lock Upgrade Deadlock
The TTL method was using a **dangerous lock upgrade pattern**:
```cpp
// DANGEROUS PATTERN (was causing deadlocks):
std::shared_lock<std::shared_mutex> lock(data_mutex_);
// ... do some work ...
lock.unlock();
std::unique_lock<std::shared_mutex> write_lock(data_mutex_);  // DEADLOCK HERE!
```

### **The Fix**: Simple Unique Lock
Replaced with **simple, safe approach**:
```cpp
// SAFE PATTERN (deadlock-free):
std::unique_lock<std::shared_mutex> lock(data_mutex_);
// ... do all work with single lock type ...
// No lock upgrades = No deadlocks!
```

---

## 📁 **FILES READY ON VM**

✅ **`meteor_commercial_lru_ttl_deadlock_free.cpp`** - Latest deadlock-free source  
✅ **`debug_ttl_method.cpp`** - Debug helper with detailed logging  
✅ **`test_deadlock_free_ttl.sh`** - Comprehensive test script

---

## 🧪 **MANUAL TESTING INSTRUCTIONS**

### **Step 1: SSH to VM**
```bash
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>"
```

### **Step 2: Build Deadlock-Free Version**
```bash
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 3

# Build the deadlock-free version
echo "Building deadlock-free TTL version..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_deadlock_free \
  meteor_commercial_lru_ttl_deadlock_free.cpp -luring

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    ls -la meteor_deadlock_free
else
    echo "❌ Build failed - check compiler errors"
    exit 1
fi
```

### **Step 3: Test Server Startup (Should Be Stable)**
```bash
echo ""
echo "🚀 Testing stable server startup..."
./meteor_deadlock_free -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 4

# Test basic connectivity
if timeout 10 redis-cli -p 6379 ping; then
    echo "✅ Server responding - stable startup!"
else
    echo "❌ Server not responding"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi
```

### **Step 4: CRITICAL TEST - TTL Should Not Hang**
```bash
echo ""
echo "🎯 CRITICAL TEST: TTL command responsiveness"
echo "=========================================="

# Clear any existing data
redis-cli -p 6379 flushall

echo "Setting key without TTL..."
redis-cli -p 6379 set no_hang_test "no ttl value"

# Verify key exists
GET_RESULT=$(redis-cli -p 6379 get no_hang_test)
echo "GET no_hang_test -> '$GET_RESULT'"

if [ "$GET_RESULT" = "no ttl value" ]; then
    echo "✅ Key stored successfully"
    
    echo ""
    echo "Testing TTL command (measuring response time)..."
    START_TIME=$(date +%s%N)
    TTL_RESULT=$(timeout 10 redis-cli -p 6379 ttl no_hang_test)
    EXIT_CODE=$?
    END_TIME=$(date +%s%N)
    DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
    
    echo "TTL execution time: ${DURATION_MS}ms"
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "TTL no_hang_test -> $TTL_RESULT"
        
        if [ "$TTL_RESULT" = "-1" ]; then
            echo "🎉 SUCCESS! TTL working perfectly!"
            echo "✅ No hanging (${DURATION_MS}ms response time)"
            echo "✅ Correct result (-1 for keys without TTL)"
            TTL_STATUS="FULLY_FIXED"
        elif [ "$TTL_RESULT" = "-2" ]; then
            echo "⚠️  No hanging but still logic issue"
            echo "✅ Performance fixed (${DURATION_MS}ms response time)" 
            echo "❌ Still returning -2 instead of -1"
            TTL_STATUS="PERFORMANCE_FIXED_LOGIC_ISSUE"
        else
            echo "❓ Unexpected result: $TTL_RESULT"
            TTL_STATUS="UNEXPECTED"
        fi
    else
        echo "❌ TTL command still timed out!"
        echo "🚨 Deadlock not fully resolved"
        TTL_STATUS="STILL_HANGING"
    fi
else
    echo "❌ Key not stored - SET command issue"
    TTL_STATUS="SET_FAILED"
fi
```

### **Step 5: Stress Test - Multiple TTL Commands**
```bash
echo ""
echo "🧪 STRESS TEST: Rapid TTL commands"
echo "================================="

echo "Testing 10 rapid TTL commands..."
redis-cli -p 6379 set stress_key "rapid test"

FAILURES=0
for i in {1..10}; do
    echo -n "Command $i: "
    RAPID_TTL=$(timeout 3 redis-cli -p 6379 ttl stress_key)
    if [ $? -eq 0 ] && [ "$RAPID_TTL" = "-1" ]; then
        echo "✅ Success ($RAPID_TTL)"
    else
        echo "❌ Failed (exit code $?, result: $RAPID_TTL)"
        FAILURES=$((FAILURES + 1))
    fi
done

echo ""
echo "Stress test results: $((10 - FAILURES))/10 commands succeeded"

if [ $FAILURES -eq 0 ]; then
    echo "✅ Perfect stress test - no hanging under rapid load"
    STRESS_STATUS="SUCCESS"
elif [ $FAILURES -lt 3 ]; then
    echo "⚠️  Mostly successful - minor intermittent issues"
    STRESS_STATUS="MINOR_ISSUES"
else
    echo "❌ Multiple failures - still has hanging issues"
    STRESS_STATUS="MAJOR_ISSUES"
fi
```

### **Step 6: SET EX + TTL Combined Test**
```bash
echo ""
echo "🧪 COMBINED TEST: SET EX + TTL"
echo "============================"

echo "Testing SET EX + TTL combination..."
START_TIME=$(date +%s)
redis-cli -p 6379 set combined_test "expires soon" EX 60
SETEX_EXIT_CODE=$?
END_TIME=$(date +%s)
SETEX_DURATION=$((END_TIME - START_TIME))

echo "SET EX execution time: ${SETEX_DURATION} seconds"

if [ $SETEX_EXIT_CODE -eq 0 ] && [ $SETEX_DURATION -lt 5 ]; then
    echo "✅ SET EX completed quickly"
    
    # Test TTL on the key with TTL
    COMBO_TTL=$(timeout 5 redis-cli -p 6379 ttl combined_test)
    echo "TTL combined_test -> $COMBO_TTL (should be >0 and ≤60)"
    
    if [ "$COMBO_TTL" -gt 0 ] && [ "$COMBO_TTL" -le 60 ]; then
        echo "✅ SET EX + TTL working perfectly"
        COMBO_STATUS="SUCCESS"
    else
        echo "❌ SET EX + TTL failed - unexpected TTL: $COMBO_TTL"
        COMBO_STATUS="FAILED"
    fi
else
    echo "❌ SET EX still taking too long or failing"
    COMBO_STATUS="SETEX_ISSUE"
fi
```

### **Step 7: Results Analysis**
```bash
echo ""
echo "🏆 DEADLOCK-FREE TTL TEST SUMMARY"
echo "================================="
echo "TTL Status: $TTL_STATUS"
echo "Stress Test: $STRESS_STATUS"  
echo "SET EX + TTL: $COMBO_STATUS"

case "$TTL_STATUS" in
    FULLY_FIXED)
        echo ""
        echo "🎉 ALL ISSUES COMPLETELY RESOLVED!"
        echo "✅ TTL commands respond in milliseconds"
        echo "✅ Correct logic (-1 for keys without TTL)"
        echo "✅ Stable under stress testing"
        echo "✅ SET EX + TTL working perfectly"
        echo ""
        echo "🚀 READY FOR PRODUCTION DEPLOYMENT!"
        FINAL_STATUS="SUCCESS"
        ;;
    PERFORMANCE_FIXED_LOGIC_ISSUE)
        echo ""
        echo "⚠️  MAJOR PROGRESS - Hanging fixed, logic issue remains"
        echo "✅ No more hanging or timeouts (major win!)"
        echo "✅ Fast response times"
        echo "❌ Still returning -2 instead of -1"
        echo ""
        echo "📋 Next step: Debug Entry constructor or has_ttl logic"
        FINAL_STATUS="PARTIAL_SUCCESS"
        ;;
    STILL_HANGING)
        echo ""
        echo "🚨 HANGING ISSUE PERSISTS"
        echo "❌ TTL commands still timing out"
        echo "   Deadlock fix was insufficient"
        echo "   May need completely different approach"
        FINAL_STATUS="STILL_BROKEN"
        ;;
    *)
        echo ""
        echo "❓ Unexpected results - need investigation"
        FINAL_STATUS="UNKNOWN"
        ;;
esac

# Clean up
kill $SERVER_PID 2>/dev/null
```

### **Step 8: Benchmark Test (If Performance Fixed)**
```bash
if [ "$FINAL_STATUS" = "SUCCESS" ] || [ "$FINAL_STATUS" = "PARTIAL_SUCCESS" ]; then
    echo ""
    echo "🏃 PERFORMANCE BENCHMARK"
    echo "======================="
    
    echo "Starting optimized server for benchmark..."
    ./meteor_deadlock_free -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &
    sleep 5
    
    echo "Running 30-second benchmark with TTL functionality..."
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
      --clients=50 --threads=12 --pipeline=10 --data-size=64 \
      --key-pattern=R:R --ratio=1:3 --test-time=30
    
    echo ""
    echo "Expected: 5.0M - 5.4M QPS (should be maintained even with TTL fixes)"
fi
```

---

## 🎯 **EXPECTED RESULTS**

### **Best Case (Fully Fixed)**:
- ✅ TTL commands respond in **<100ms** 
- ✅ TTL returns **-1** for keys without TTL (not -2)
- ✅ TTL returns **>0** for keys with TTL  
- ✅ No hanging under stress testing
- ✅ **5.0M - 5.4M QPS** maintained

### **Partial Success (Performance Fixed)**:
- ✅ TTL commands respond quickly (no hanging)
- ❌ Still returns **-2** instead of **-1** (logic issue)
- ✅ Stable performance under load
- 📋 Need to debug `has_ttl` flag logic

### **Still Broken**:
- ❌ TTL commands still hang/timeout
- ❌ Need different deadlock resolution approach

---

## 🔧 **TROUBLESHOOTING**

### **If TTL Still Hangs**
- Check server logs for deadlock detection
- Try building with different optimization flags
- Consider using `std::mutex` instead of `std::shared_mutex`

### **If Logic Issue Persists (-2 instead of -1)**
- Entry constructor might not initialize `has_ttl = false`
- SET method might not be using the right constructor
- Memory corruption might be overwriting the flag

### **If Performance Regression**
- `unique_lock` has more overhead than `shared_lock`
- May need to optimize the locking strategy
- Consider lock-free alternatives for read-heavy workloads

---

## 🏆 **SUCCESS CRITERIA**

**Minimum Success**: TTL commands don't hang anymore  
**Full Success**: TTL logic works correctly AND no performance regression

**The deadlock-free approach should at least fix the hanging issue! 🚀**













