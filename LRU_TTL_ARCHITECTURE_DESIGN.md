# METEOR LRU+TTL ARCHITECTURE DESIGN

## CURRENT BASELINE ANALYSIS

**✅ Existing Cache Architecture (Preserved):**
- **VLLHashTable**: `std::unordered_map<std::string, Entry>` per core
- **HybridCache**: Memory + SSD tiering with access tracking
- **Shared-Nothing**: Each core owns its data (zero locking)
- **Access Tracking**: Already has `last_access_` and `access_frequency_`

**✅ Current Entry Structure:**
```cpp
struct Entry {
    std::string key;
    std::string value;
    // No TTL currently
};
```

## INDUSTRY RESEARCH INSIGHTS

**Redis Approach:**
- Per-key expiration timestamps
- Lazy expiration during key access
- Background periodic cleanup
- LRU eviction when memory limit reached

**Dragonfly Approach:**
- Modern per-shard (core) memory management
- Combined LRU+TTL for optimal memory usage
- Efficient expiration tracking

## METEOR LRU+TTL DESIGN

### 1. Enhanced Entry Structure
```cpp
struct Entry {
    std::string key;
    std::string value;
    std::chrono::steady_clock::time_point created_at;
    std::chrono::steady_clock::time_point expire_at;  // NEW: TTL support
    std::chrono::steady_clock::time_point last_access; // NEW: LRU support
    bool has_expiration;  // NEW: TTL enabled flag
    
    Entry(const std::string& k, const std::string& v) 
        : key(k), value(v), 
          created_at(std::chrono::steady_clock::now()),
          expire_at(std::chrono::steady_clock::time_point::max()),
          last_access(created_at),
          has_expiration(false) {}
};
```

### 2. VLLHashTable Enhancements
```cpp
class VLLHashTable {
private:
    std::unordered_map<std::string, Entry> data_;
    
    // LRU tracking (minimal overhead)
    mutable std::chrono::steady_clock::time_point last_cleanup_;
    static constexpr auto CLEANUP_INTERVAL = std::chrono::minutes(1);
    
    // Memory limits
    size_t max_entries_;
    static constexpr size_t DEFAULT_MAX_ENTRIES = 1000000; // Per core
    
    void lazy_cleanup() const; // Remove expired entries
    void lru_evict(); // Evict oldest entries when at capacity
    bool is_expired(const Entry& entry) const;
    
public:
    bool set(const std::string& key, const std::string& value);
    bool set_with_ttl(const std::string& key, const std::string& value, std::chrono::seconds ttl);
    std::optional<std::string> get(const std::string& key);
    bool del(const std::string& key);
    
    // TTL commands
    bool expire(const std::string& key, std::chrono::seconds ttl);
    std::optional<std::chrono::seconds> ttl(const std::string& key);
    bool persist(const std::string& key); // Remove TTL
};
```

### 3. Command Processing Integration

**Enhanced Command Detection:**
```cpp
inline bool is_expire_command(std::string_view cmd);
inline bool is_ttl_command(std::string_view cmd);  
inline bool is_persist_command(std::string_view cmd);
```

**New Command Processing (in execute_single_operation_optimized):**
```cpp
// EXPIRE key seconds
if (zero_copy::is_expire_command(op.command)) {
    bool success = cache_->expire(std::string(op.key), std::chrono::seconds(std::stoi(std::string(op.value))));
    return success ? ResponseInfo(":1\r\n", 4) : ResponseInfo(":0\r\n", 4);
}

// TTL key  
if (zero_copy::is_ttl_command(op.command)) {
    auto ttl_seconds = cache_->ttl(std::string(op.key));
    if (ttl_seconds) {
        std::string response = ":" + std::to_string(ttl_seconds->count()) + "\r\n";
        return ResponseInfo(response.c_str(), response.length(), false);
    } else {
        return ResponseInfo(":-1\r\n", 5); // Key doesn't exist or no TTL
    }
}

// PERSIST key
if (zero_copy::is_persist_command(op.command)) {
    bool success = cache_->persist(std::string(op.key));
    return success ? ResponseInfo(":1\r\n", 4) : ResponseInfo(":0\r\n", 4);
}
```

### 4. Memory Management Strategy

**LRU Eviction Policy:**
- When `data_.size() >= max_entries_`, evict 10% of oldest entries
- Use `last_access` timestamp for LRU ordering
- Eviction happens during SET operations (proactive)

**TTL Cleanup Strategy:**
- **Lazy Cleanup**: Check expiration during GET operations
- **Periodic Cleanup**: Every 1 minute, scan and remove expired entries
- **Proactive Cleanup**: During SET when approaching memory limits

### 5. Performance Guarantees

**✅ Zero Regression Requirements:**
- **GET Performance**: Add single `is_expired()` check (nanoseconds overhead)
- **SET Performance**: LRU update is O(1) timestamp assignment  
- **Memory Overhead**: +24 bytes per entry (timestamps + bool)
- **No Locking**: Maintains shared-nothing per-core architecture
- **Pipeline Correctness**: No changes to routing or cross-core logic

**✅ Industry-Leading Features:**
- **Redis-Compatible Commands**: EXPIRE, TTL, PERSIST
- **Efficient Memory Management**: Prevents OOM via LRU eviction
- **Modern Architecture**: Per-core isolation like Dragonfly
- **Lazy Expiration**: Minimizes CPU overhead
- **Configurable Limits**: Per-core memory limits

## IMPLEMENTATION PLAN

1. **Phase 1**: Enhance Entry struct and VLLHashTable  
2. **Phase 2**: Add TTL/LRU methods with lazy cleanup
3. **Phase 3**: Integrate new commands into command processing
4. **Phase 4**: Add periodic cleanup background task
5. **Phase 5**: Comprehensive testing and performance validation

## VALIDATION STRATEGY

**Correctness Tests:**
- TTL expiration accuracy
- LRU eviction correctness  
- Memory limit enforcement
- Command compatibility with Redis clients

**Performance Tests:**
- Single GET/SET performance (must match baseline)
- Pipeline performance (must match baseline)
- Memory usage under load
- Expiration cleanup efficiency

**Regression Tests:**
- All existing single command tests must pass
- All existing pipeline tests must pass
- Cross-core routing unchanged
- No correctness regressions

This design ensures meteor becomes an **industry-leading cache server** while maintaining **zero performance regression** and **zero correctness issues**.












