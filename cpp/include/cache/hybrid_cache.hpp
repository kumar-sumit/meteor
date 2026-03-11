#pragma once

#include "cache.hpp"
#include "../storage/storage_backend.hpp"
#include "../utils/thread_pool.hpp"
#include "../utils/memory_pool.hpp"
#include <unordered_map>
#include <shared_mutex>
#include <atomic>
#include <thread>
#include <condition_variable>

namespace meteor {
namespace cache {

// High-performance hybrid cache with smart overflow detection
class HybridCache : public Cache {
public:
    explicit HybridCache(const CacheConfig& config);
    ~HybridCache() override;
    
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
    // Memory cache entry
    struct MemoryEntry {
        std::string value;
        std::chrono::time_point<std::chrono::steady_clock> created_at;
        std::chrono::time_point<std::chrono::steady_clock> expires_at;
        std::chrono::time_point<std::chrono::steady_clock> last_accessed;
        size_t access_count = 0;
        bool has_ttl = false;
        bool is_hot = false;
        
        explicit MemoryEntry(const std::string& v, std::chrono::milliseconds ttl = std::chrono::milliseconds::zero())
            : value(v), has_ttl(ttl.count() > 0) {
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
            access_count++;
        }
        
        size_t memory_usage() const {
            return sizeof(MemoryEntry) + value.size();
        }
    };
    
    // Configuration
    CacheConfig config_;
    
    // Memory cache
    mutable std::shared_mutex memory_mutex_;
    std::unordered_map<std::string, MemoryEntry> memory_cache_;
    
    // SSD storage backend
    std::unique_ptr<storage::StorageBackend> ssd_backend_;
    
    // Thread pools
    std::unique_ptr<utils::ThreadPool> worker_pool_;
    std::unique_ptr<utils::ThreadPool> io_pool_;
    
    // Memory pools
    std::unique_ptr<utils::BufferPool> buffer_pool_;
    
    // Statistics
    mutable std::atomic<uint64_t> memory_hits_{0};
    mutable std::atomic<uint64_t> memory_misses_{0};
    mutable std::atomic<uint64_t> ssd_hits_{0};
    mutable std::atomic<uint64_t> ssd_misses_{0};
    mutable std::atomic<uint64_t> puts_{0};
    mutable std::atomic<uint64_t> removes_{0};
    mutable std::atomic<uint64_t> evictions_{0};
    mutable std::atomic<uint64_t> memory_bytes_{0};
    
    // Lifecycle
    std::atomic<bool> running_{false};
    std::atomic<bool> shutdown_{false};
    
    // Background threads
    std::thread eviction_thread_;
    std::thread cleanup_thread_;
    std::thread metrics_thread_;
    
    // Condition variables for background threads
    std::condition_variable eviction_cv_;
    std::condition_variable cleanup_cv_;
    std::condition_variable metrics_cv_;
    std::mutex eviction_mutex_;
    std::mutex cleanup_mutex_;
    std::mutex metrics_mutex_;
    
    // Private methods
    bool get_from_memory(const std::string& key, std::string& value);
    bool get_from_ssd(const std::string& key, std::string& value);
    bool put_to_memory(const std::string& key, const std::string& value, std::chrono::milliseconds ttl);
    bool put_to_ssd(const std::string& key, const std::string& value, std::chrono::milliseconds ttl);
    
    void evict_from_memory();
    void cleanup_expired_entries();
    void update_metrics();
    
    void start_background_threads();
    void stop_background_threads();
    
    bool should_evict() const;
    std::vector<std::string> select_eviction_candidates();
    
    void eviction_worker();
    void cleanup_worker();
    void metrics_worker();
};

} // namespace cache
} // namespace meteor 