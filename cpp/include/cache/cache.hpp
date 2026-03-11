#pragma once

#include <memory>
#include <string>
#include <vector>
#include <chrono>
#include <optional>
#include <functional>
#include "../utils/memory_pool.hpp"

namespace meteor {
namespace cache {

// Forward declarations
class CacheEntry;
class CacheStats;

// Cache interface
class Cache {
public:
    virtual ~Cache() = default;
    
    // Core operations
    virtual bool get(const std::string& key, std::string& value) = 0;
    virtual bool get(utils::span<const char> key, std::vector<char>& value) = 0;
    virtual bool put(const std::string& key, const std::string& value, 
                     std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) = 0;
    virtual bool put(utils::span<const char> key, utils::span<const char> value,
                     std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) = 0;
    virtual bool remove(const std::string& key) = 0;
    virtual bool contains(const std::string& key) = 0;
    virtual void clear() = 0;
    
    // Batch operations
    virtual std::vector<std::optional<std::string>> multi_get(
        const std::vector<std::string>& keys) = 0;
    virtual bool multi_put(const std::vector<std::pair<std::string, std::string>>& pairs,
                          std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) = 0;
    virtual bool multi_remove(const std::vector<std::string>& keys) = 0;
    
    // Statistics and monitoring
    virtual CacheStats get_stats() const = 0;
    virtual size_t size() const = 0;
    virtual size_t memory_usage() const = 0;
    
    // Configuration
    virtual void set_max_memory(size_t bytes) = 0;
    virtual void set_max_entries(size_t count) = 0;
    virtual void set_default_ttl(std::chrono::milliseconds ttl) = 0;
    
    // Lifecycle
    virtual void start() = 0;
    virtual void stop() = 0;
    virtual void flush() = 0;
    
    // Health check
    virtual bool is_healthy() const = 0;
};

// Cache statistics
struct CacheStats {
    uint64_t hits = 0;
    uint64_t misses = 0;
    uint64_t puts = 0;
    uint64_t removes = 0;
    uint64_t evictions = 0;
    uint64_t memory_hits = 0;
    uint64_t memory_misses = 0;
    uint64_t ssd_hits = 0;
    uint64_t ssd_misses = 0;
    uint64_t total_entries = 0;
    uint64_t memory_entries = 0;
    uint64_t ssd_entries = 0;
    uint64_t memory_bytes = 0;
    uint64_t ssd_bytes = 0;
    double hit_ratio = 0.0;
    double memory_hit_ratio = 0.0;
    double ssd_hit_ratio = 0.0;
    std::chrono::milliseconds avg_get_latency = std::chrono::milliseconds::zero();
    std::chrono::milliseconds avg_put_latency = std::chrono::milliseconds::zero();
    std::chrono::milliseconds uptime = std::chrono::milliseconds::zero();
};

// Cache entry metadata
struct CacheEntry {
    std::string key;
    std::string value;
    std::chrono::time_point<std::chrono::steady_clock> created_at;
    std::chrono::time_point<std::chrono::steady_clock> expires_at;
    std::chrono::time_point<std::chrono::steady_clock> last_accessed;
    size_t access_count = 0;
    bool has_ttl = false;
    bool is_hot = false;
    bool is_dirty = false;
    
    bool is_expired() const {
        return has_ttl && std::chrono::steady_clock::now() > expires_at;
    }
    
    size_t memory_usage() const {
        return sizeof(CacheEntry) + key.size() + value.size();
    }
    
    void touch() {
        last_accessed = std::chrono::steady_clock::now();
        access_count++;
    }
};

// Cache configuration
struct CacheConfig {
    size_t max_memory_bytes = 256 * 1024 * 1024; // 256MB
    size_t max_memory_entries = 100000;
    size_t ssd_max_file_size = 2 * 1024 * 1024 * 1024UL; // 2GB
    size_t ssd_page_size = 4096;
    std::string ssd_directory = "/tmp/meteor_cache";
    std::string tiered_storage_prefix = "";
    
    // Sharding settings
    size_t shard_count = 0; // 0 = auto-detect
    size_t max_entries = 100000;
    bool enable_simd = true;
    bool enable_fiber_scheduling = true;
    
    // Performance settings
    size_t worker_threads = 0; // 0 = auto-detect
    size_t io_threads = 0; // 0 = auto-detect
    bool enable_compression = false;
    bool enable_encryption = false;
    bool enable_async_io = true;
    bool enable_zero_copy = true;
    
    // Eviction settings
    double eviction_threshold = 0.85; // 85% full
    size_t eviction_batch_size = 100;
    std::chrono::milliseconds eviction_interval = std::chrono::seconds(10);
    
    // TTL settings
    std::chrono::milliseconds default_ttl = std::chrono::milliseconds::zero();
    std::chrono::milliseconds cleanup_interval = std::chrono::seconds(30);
    
    // Monitoring
    bool enable_metrics = true;
    std::chrono::milliseconds metrics_interval = std::chrono::seconds(10);
};

// Cache factory functions
std::unique_ptr<Cache> create_memory_cache(const CacheConfig& config);
std::unique_ptr<Cache> create_ssd_cache(const CacheConfig& config);
std::unique_ptr<Cache> create_hybrid_cache(const CacheConfig& config);

} // namespace cache
} // namespace meteor 