#pragma once

#include <memory>
#include <string>
#include <vector>
#include <chrono>
#include <functional>
#include <future>
#include <optional>
#include "../utils/memory_pool.hpp"

namespace meteor {
namespace storage {

// Forward declarations
class StorageEntry;
class StorageStats;

// Storage backend interface
class StorageBackend {
public:
    virtual ~StorageBackend() = default;
    
    // Synchronous operations
    virtual bool get(const std::string& key, std::string& value) = 0;
    virtual bool get(utils::span<const char> key, std::vector<char>& value) = 0;
    virtual bool put(const std::string& key, const std::string& value, 
                     std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) = 0;
    virtual bool put(utils::span<const char> key, utils::span<const char> value,
                     std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) = 0;
    virtual bool remove(const std::string& key) = 0;
    virtual bool contains(const std::string& key) = 0;
    virtual void clear() = 0;
    
    // Asynchronous operations
    virtual std::future<bool> get_async(const std::string& key, std::string& value) = 0;
    virtual std::future<bool> put_async(const std::string& key, const std::string& value,
                                       std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) = 0;
    virtual std::future<bool> remove_async(const std::string& key) = 0;
    
    // Batch operations
    virtual std::vector<std::optional<std::string>> multi_get(
        const std::vector<std::string>& keys) = 0;
    virtual bool multi_put(const std::vector<std::pair<std::string, std::string>>& pairs,
                          std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) = 0;
    
    // Statistics and monitoring
    virtual struct StorageStats get_stats() const = 0;
    virtual size_t size() const = 0;
    virtual size_t disk_usage() const = 0;
    
    // Lifecycle management
    virtual void start() {}
    virtual void stop() {}
    virtual void flush() {}
    
    // Configuration
    virtual void set_max_size(size_t bytes) {}
    virtual void set_max_entries(size_t count) {}
    virtual void set_compression_enabled(bool enabled) {}
    virtual void set_encryption_enabled(bool enabled) {}
};

// Storage statistics
struct StorageStats {
    uint64_t reads = 0;
    uint64_t writes = 0;
    uint64_t deletes = 0;
    uint64_t cache_hits = 0;
    uint64_t cache_misses = 0;
    uint64_t bytes_read = 0;
    uint64_t bytes_written = 0;
    uint64_t total_entries = 0;
    uint64_t total_size = 0;
    uint64_t disk_usage = 0;
    uint64_t memory_usage = 0;
    double hit_ratio = 0.0;
    double compression_ratio = 0.0;
    std::chrono::milliseconds avg_read_latency = std::chrono::milliseconds::zero();
    std::chrono::milliseconds avg_write_latency = std::chrono::milliseconds::zero();
};

// Storage entry metadata
struct StorageEntry {
    std::string key;
    std::string value;
    std::chrono::time_point<std::chrono::steady_clock> created_at;
    std::chrono::time_point<std::chrono::steady_clock> expires_at;
    std::chrono::time_point<std::chrono::steady_clock> last_accessed;
    size_t access_count = 0;
    bool has_ttl = false;
    bool is_compressed = false;
    bool is_encrypted = false;
    
    bool is_expired() const {
        return has_ttl && std::chrono::steady_clock::now() > expires_at;
    }
    
    size_t memory_usage() const {
        return sizeof(StorageEntry) + key.size() + value.size();
    }
};

// Storage configuration
struct StorageConfig {
    std::string storage_dir = "/tmp/meteor_storage";
    size_t max_memory_usage = 256 * 1024 * 1024; // 256MB
    size_t max_entries = 1000000;
    size_t max_file_size = 2 * 1024 * 1024 * 1024UL; // 2GB
    size_t page_size = 4096;
    bool enable_compression = false;
    bool enable_encryption = false;
    bool enable_async_io = true;
    bool enable_mmap = true;
    std::chrono::milliseconds default_ttl = std::chrono::milliseconds::zero();
    std::chrono::milliseconds cleanup_interval = std::chrono::seconds(30);
    std::chrono::milliseconds sync_interval = std::chrono::seconds(5);
};

// Factory functions
std::unique_ptr<StorageBackend> create_file_storage_backend(const std::string& storage_dir = "/tmp/meteor_storage");
std::unique_ptr<StorageBackend> create_memory_storage_backend();
std::unique_ptr<StorageBackend> create_hybrid_storage_backend(const StorageConfig& config);

} // namespace storage
} // namespace meteor 