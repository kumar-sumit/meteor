#pragma once

#include "cache.hpp"
#include "../utils/thread_pool.hpp"
#include "../utils/memory_pool.hpp"
#include "../utils/hash.hpp"
#include <vector>
#include <memory>
#include <atomic>
#include <thread>
#include <mutex>
#include <shared_mutex>
#include <unordered_map>
#include <immintrin.h>

namespace meteor {
namespace cache {

// Forward declarations
class ShardedCache;

// Per-shard cache entry with optimized memory layout
struct alignas(64) CacheEntry {
    std::string key;
    std::string value;
    std::chrono::time_point<std::chrono::steady_clock> created_at;
    std::chrono::time_point<std::chrono::steady_clock> expires_at;
    std::chrono::time_point<std::chrono::steady_clock> last_accessed;
    std::atomic<uint32_t> access_count{0};
    std::atomic<bool> is_hot{false};
    bool has_ttl = false;
    
    explicit CacheEntry(std::string k, std::string v, std::chrono::milliseconds ttl = std::chrono::milliseconds::zero())
        : key(std::move(k)), value(std::move(v)), has_ttl(ttl.count() > 0) {
        auto now = std::chrono::steady_clock::now();
        created_at = now;
        last_accessed = now;
        
        if (has_ttl) {
            expires_at = now + ttl;
        }
    }
    
    bool is_expired() const {
        return has_ttl && std::chrono::steady_clock::now() > expires_at;
    }
    
    void touch() {
        last_accessed = std::chrono::steady_clock::now();
        access_count.fetch_add(1, std::memory_order_relaxed);
    }
    
    size_t memory_usage() const {
        return sizeof(CacheEntry) + key.size() + value.size();
    }
};

// Lock-free hash table bucket
struct alignas(64) HashBucket {
    std::atomic<CacheEntry*> entry{nullptr};
    std::atomic<uint64_t> version{0};
    
    // Padding to avoid false sharing
    char padding[64 - sizeof(std::atomic<CacheEntry*>) - sizeof(std::atomic<uint64_t>)];
};

// Individual cache shard with lock-free operations
class CacheShard {
public:
    explicit CacheShard(size_t initial_capacity = 16384);
    ~CacheShard();
    
    // Non-copyable, movable
    CacheShard(const CacheShard&) = delete;
    CacheShard& operator=(const CacheShard&) = delete;
    CacheShard(CacheShard&&) = default;
    CacheShard& operator=(CacheShard&&) = default;
    
    // Core operations
    bool get(const std::string& key, std::string& value);
    bool put(const std::string& key, const std::string& value, std::chrono::milliseconds ttl = std::chrono::milliseconds::zero());
    bool remove(const std::string& key);
    bool contains(const std::string& key);
    
    // Batch operations
    std::vector<std::optional<std::string>> multi_get(const std::vector<std::string>& keys);
    bool multi_put(const std::vector<std::pair<std::string, std::string>>& pairs, std::chrono::milliseconds ttl = std::chrono::milliseconds::zero());
    bool multi_remove(const std::vector<std::string>& keys);
    
    // Management
    void clear();
    void evict_expired();
    void resize(size_t new_capacity);
    
    // Statistics
    size_t size() const { return size_.load(std::memory_order_relaxed); }
    size_t capacity() const { return capacity_.load(std::memory_order_relaxed); }
    size_t memory_usage() const { return memory_usage_.load(std::memory_order_relaxed); }
    
    // Performance metrics
    uint64_t get_hit_count() const { return hit_count_.load(std::memory_order_relaxed); }
    uint64_t get_miss_count() const { return miss_count_.load(std::memory_order_relaxed); }
    uint64_t get_eviction_count() const { return eviction_count_.load(std::memory_order_relaxed); }
    
private:
    // Hash table implementation
    std::unique_ptr<HashBucket[]> buckets_;
    std::atomic<size_t> capacity_{0};
    std::atomic<size_t> size_{0};
    std::atomic<size_t> memory_usage_{0};
    
    // Memory management
    std::unique_ptr<utils::MemoryPool> memory_pool_;
    
    // Statistics
    std::atomic<uint64_t> hit_count_{0};
    std::atomic<uint64_t> miss_count_{0};
    std::atomic<uint64_t> eviction_count_{0};
    
    // Helper methods
    size_t hash_key(const std::string& key) const;
    size_t find_bucket(const std::string& key) const;
    bool try_insert(size_t bucket_idx, std::unique_ptr<CacheEntry> entry);
    bool try_update(size_t bucket_idx, const std::string& key, const std::string& value, std::chrono::milliseconds ttl);
    std::unique_ptr<CacheEntry> try_remove(size_t bucket_idx, const std::string& key);
    void rehash_if_needed();
    
    // SIMD-optimized operations
    bool simd_key_compare(const char* key1, const char* key2, size_t len) const;
    uint64_t simd_hash(const char* data, size_t len) const;
};

// Shared-nothing sharded cache with per-thread affinity
class ShardedCache : public Cache {
public:
    explicit ShardedCache(const CacheConfig& config);
    ~ShardedCache() override;
    
    // Cache interface implementation
    bool get(const std::string& key, std::string& value) override;
    bool get(utils::span<const char> key, std::vector<char>& value) override;
    bool put(const std::string& key, const std::string& value, 
             std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) override;
    bool put(utils::span<const char> key, utils::span<const char> value,
             std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) override;
    bool remove(const std::string& key) override;
    bool contains(const std::string& key) override;
    void clear() override;
    
    std::vector<std::optional<std::string>> multi_get(
        const std::vector<std::string>& keys) override;
    bool multi_put(const std::vector<std::pair<std::string, std::string>>& pairs,
                  std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) override;
    bool multi_remove(const std::vector<std::string>& keys) override;
    
    CacheStats get_stats() const override;
    size_t size() const override;
    size_t memory_usage() const override;
    
    void set_max_memory(size_t bytes) override;
    void set_max_entries(size_t count) override;
    void set_default_ttl(std::chrono::milliseconds ttl) override;
    
    void start() override;
    void stop() override;
    void flush() override;
    
    bool is_healthy() const override;

private:
    // Configuration
    CacheConfig config_;
    
    // Sharding
    std::vector<std::unique_ptr<CacheShard>> shards_;
    size_t shard_count_;
    size_t shard_mask_;
    
    // Thread affinity
    thread_local static size_t thread_shard_hint_;
    
    // Background tasks
    std::atomic<bool> running_{false};
    std::thread maintenance_thread_;
    
    // Helper methods
    size_t get_shard_index(const std::string& key) const;
    size_t get_shard_index(utils::span<const char> key) const;
    size_t get_preferred_shard() const;
    void maintenance_loop();
    
    // SIMD-optimized key hashing
    uint64_t fast_hash(const char* data, size_t len) const;
    uint64_t fast_hash(const std::string& key) const;
    uint64_t fast_hash(utils::span<const char> key) const;
};

} // namespace cache
} // namespace meteor 