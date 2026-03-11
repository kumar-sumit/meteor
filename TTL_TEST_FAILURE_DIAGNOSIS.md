# 🔍 **TTL TEST FAILURE DIAGNOSIS & SOLUTIONS**

## 📋 **COMMON TTL TEST FAILURES**

### **Test Case 1: Key without TTL returns wrong value**
**Expected**: `TTL no_ttl_key` → `-1`  
**Common Issues**:
- Returns `-2` instead of `-1` → Key not being stored properly
- Returns positive number → TTL accidentally set during SET

**Diagnostic Commands**:
```bash
redis-cli -p 6379 set debug_key "test value"
redis-cli -p 6379 get debug_key          # Should return: "test value"  
redis-cli -p 6379 ttl debug_key          # Should return: -1
```

### **Test Case 2: Non-existent key returns wrong value**
**Expected**: `TTL nonexistent_key` → `-2`
**Common Issues**:
- Returns `-1` → Logic error in TTL method
- Server crash → Connection issues

### **Test Case 3: Key with TTL returns wrong value**
**Expected**: `SET key val EX 30` → `TTL key` → `>0 and ≤30`
**Common Issues**:
- Returns `-1` → TTL not being set properly during SET EX
- Returns `-2` → Key not stored or immediately expired

### **Test Case 4: EXPIRE command fails**
**Expected**: `EXPIRE key 25` → `1`, then `TTL key` → `>0 and ≤25`
**Common Issues**:
- EXPIRE returns `0` → Key doesn't exist or command parsing error
- TTL returns wrong value → EXPIRE logic not working

---

## 🔧 **QUICK DIAGNOSTIC STEPS**

### **Step 1: Check Server Status**
```bash
# On VM:
ps aux | grep meteor                    # Check if server is running
redis-cli -p 6379 ping                 # Test connectivity
```

### **Step 2: Manual TTL Test**
```bash
# Test each case individually:
redis-cli -p 6379 flushall             # Clear all data
redis-cli -p 6379 set test1 "no ttl"   # Set without TTL
redis-cli -p 6379 ttl test1            # Should be -1

redis-cli -p 6379 ttl nonexistent      # Should be -2

redis-cli -p 6379 set test3 "with ttl" EX 60
redis-cli -p 6379 ttl test3            # Should be >0 and ≤60

redis-cli -p 6379 set test4 "for expire"
redis-cli -p 6379 expire test4 30      # Should return 1
redis-cli -p 6379 ttl test4            # Should be >0 and ≤30
```

### **Step 3: Check Logs**
```bash
# Check server logs for errors:
tail -50 /mnt/externalDisk/meteor/*.log
```

---

## 🛠️ **POTENTIAL FIXES**

### **Fix 1: SET Method Thread Safety Issue**
If Test 1 fails (key without TTL), the issue might be in the `set` method:

```cpp
// Check if this logic is in the set method:
bool set(const std::string& key, const std::string& value) {
    std::unique_lock<std::shared_mutex> lock(data_mutex_);
    
    // Create entry WITHOUT TTL - ensure has_ttl = false
    Entry new_entry(key, value);        // ← This constructor should set has_ttl = false
    new_entry.update_access();
    data_[key] = new_entry;
    
    return true;
}
```

### **Fix 2: TTL Method Logic Error**
If multiple tests fail, check the `ttl` method logic:

```cpp
long ttl(const std::string& key) {
    // First check lazy expiry
    if (lazy_expire_if_needed(key)) {
        return -2; // Key was expired and removed
    }
    
    std::shared_lock<std::shared_mutex> lock(data_mutex_);
    auto it = data_.find(key);
    
    if (it == data_.end()) {
        return -2; // Key doesn't exist ← Should work for Test 2
    }
    
    if (!it->second.has_ttl) {
        return -1; // No TTL set ← Should work for Test 1
    }
    
    // Calculate remaining time ← Should work for Test 3
    auto remaining = it->second.expiry_time - std::chrono::steady_clock::now();
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(remaining).count();
    
    return std::max(0L, seconds);
}
```

### **Fix 3: Entry Constructor Issue**
Check if the Entry constructor properly initializes `has_ttl`:

```cpp
// In Entry struct - make sure this is correct:
Entry(const std::string& k, const std::string& v) 
    : key(k), value(v), last_access(std::chrono::steady_clock::now()),
      expiry_time{}, has_ttl(false), lru_clock(0) {}  // ← has_ttl MUST be false
```

---

## 📊 **EXPECTED vs ACTUAL RESULTS TABLE**

Please fill in what you observed:

| **Test** | **Command** | **Expected** | **Your Result** | **Status** |
|----------|-------------|--------------|-----------------|------------|
| **Test 1** | `SET no_ttl_key "val"` → `TTL no_ttl_key` | `-1` | `?` | `?` |
| **Test 2** | `TTL nonexistent_key` | `-2` | `?` | `?` |
| **Test 3** | `SET ttl_key "val" EX 30` → `TTL ttl_key` | `>0 and ≤30` | `?` | `?` |
| **Test 4** | `EXPIRE test 25` → `TTL test` | `1` then `>0 and ≤25` | `?` | `?` |

---

## 🎯 **NEXT STEPS**

1. **Share your test output** - I can pinpoint the exact issue
2. **Run manual diagnostic commands** above
3. **Check which specific test failed** and we'll apply the targeted fix
4. **Re-test after fix** to confirm resolution

**Common Quick Fixes**:
- If **Test 1 fails**: Entry constructor or SET method issue
- If **Test 2 fails**: TTL method logic error  
- If **Test 3 fails**: SET EX command parsing problem
- If **Test 4 fails**: EXPIRE command implementation issue

Please share the specific test results and I'll provide the exact fix! 🔧













