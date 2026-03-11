#pragma once

#include <atomic>
#include <chrono>
#include <memory>
#include <optional>
#include <shared_mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace meteor {
namespace storage {
class OptimizedSSDStorage;
}

namespace utils {
class MemoryPool;
class ThreadPool;
}

namespace cache {

struct Config {
    // Memory cache configuration
    size_t max_memory_entries = 100000;
    size_t max_memory_bytes = 256 * 1024 * 1024; // 256MB
    std::chrono::seconds default_ttl{3600}; // 1 hour
    
    // SSD storage configuration
    std::string tiered_prefix; // Empty = pure in-memory
    size_t page_size = 4096;
    size_t max_file_size = 2LL * 1024 * 1024 * 1024; // 2GB
    
    // Performance configuration
    size_t buffer_pool_size = 1024;
    size_t io_threads = 4;
    bool enable_compression = true;
    bool enable_bloom_filter = true;
};

struct CacheEntry {
    std::string value;
    std::chrono::steady_clock::time_point expiry_time;
};

struct CacheStats {
    uint64_t memory_hits = 0;
    uint64_t memory_misses = 0;
    uint64_t ssd_reads = 0;
    uint64_t ssd_writes = 0;
    uint64_t ssd_errors = 0;
    uint64_t memory_entries = 0;
    uint64_t memory_usage = 0;
    uint64_t evictions = 0;
    bool ssd_enabled = false;
};

class HybridCache {
public:
    explicit HybridCache(const Config& config);
    ~HybridCache();

    // Disable copy and move
    HybridCache(const HybridCache&) = delete;
    HybridCache& operator=(const HybridCache&) = delete;
    HybridCache(HybridCache&&) = delete;
    HybridCache& operator=(HybridCache&&) = delete;

    // Start/stop the cache
    bool start();
    void stop();

    // Cache operations
    bool put(const std::string& key, const std::string& value, 
             std::chrono::seconds ttl = std::chrono::seconds(0));
    std::optional<std::string> get(const std::string& key);
    bool remove(const std::string& key);
    bool contains(const std::string& key);
    void clear();

    // Statistics
    CacheStats get_stats() const;

private:
    Config config_;
    std::unordered_map<std::string, CacheEntry> memory_cache_;
    std::shared_mutex cache_mutex_;
    
    // Storage backend
    std::unique_ptr<storage::OptimizedSSDStorage> ssd_storage_;
    bool use_ssd_;
    
    // Statistics (these remain atomic for thread safety)
    std::atomic<uint64_t> hit_count_{0};
    std::atomic<uint64_t> miss_count_{0};
    std::atomic<uint64_t> eviction_count_{0};
    std::atomic<uint64_t> memory_usage_{0};
    std::atomic<bool> running_{false};
    
    // Memory and thread pools
    std::unique_ptr<utils::MemoryPool> memory_pool_;
    std::unique_ptr<utils::ThreadPool> thread_pool_;
    
    // Private methods
    void evict_expired_entries();
    void evict_lru_entries();
    bool should_evict_to_ssd(const std::string& key, const std::string& value);
    void async_write_to_ssd(const std::string& key, const std::string& value);
    std::optional<std::string> read_from_ssd(const std::string& key);
    
    // Background tasks
    void background_maintenance();
    std::thread maintenance_thread_;
    std::atomic<bool> maintenance_running_{false};
    
    // Utility methods
    bool is_expired(const CacheEntry& entry) const;
    size_t calculate_entry_size(const std::string& key, const std::string& value) const;
    std::chrono::steady_clock::time_point calculate_expiry_time(std::chrono::seconds ttl) const;
};

} // namespace cache
} // namespace meteor 