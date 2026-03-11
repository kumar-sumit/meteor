#include "meteor/cache/hybrid_cache.hpp"
#include "meteor/storage/optimized_ssd_storage.hpp"
#include "meteor/utils/memory_pool.hpp"
#include "meteor/utils/thread_pool.hpp"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <iostream>

namespace meteor {
namespace cache {

HybridCache::HybridCache(const Config& config)
    : config_(config)
    , memory_cache_(config.max_memory_entries)
    , memory_usage_(0)
    , hit_count_(0)
    , miss_count_(0)
    , eviction_count_(0)
    , running_(false)
    , memory_pool_(std::make_unique<utils::MemoryPool>(config.buffer_pool_size))
    , thread_pool_(std::make_unique<utils::ThreadPool>(config.io_threads))
{
    // Initialize SSD storage if tiered_prefix is provided
    if (!config.tiered_prefix.empty()) {
        try {
            ssd_storage_ = std::make_unique<storage::OptimizedSSDStorage>(
                config.tiered_prefix,
                config.page_size,
                config.max_file_size
            );
            use_ssd_ = true;
        } catch (const std::exception& e) {
            std::cerr << "Failed to initialize SSD storage: " << e.what() << std::endl;
            use_ssd_ = false;
        }
    } else {
        use_ssd_ = false;
    }
}

HybridCache::~HybridCache() {
    stop();
}

void HybridCache::start() {
    if (running_.exchange(true)) {
        return; // Already running
    }

    // Start cleanup thread
    cleanup_thread_ = std::thread([this]() {
        while (running_) {
            std::this_thread::sleep_for(std::chrono::seconds(config_.cleanup_interval));
            cleanup_expired_entries();
        }
    });

    // Start metrics thread
    metrics_thread_ = std::thread([this]() {
        while (running_) {
            std::this_thread::sleep_for(std::chrono::seconds(config_.metrics_interval));
            update_metrics();
        }
    });
}

void HybridCache::stop() {
    if (!running_.exchange(false)) {
        return; // Already stopped
    }

    if (cleanup_thread_.joinable()) {
        cleanup_thread_.join();
    }
    if (metrics_thread_.joinable()) {
        metrics_thread_.join();
    }

    // Sync SSD storage
    if (ssd_storage_) {
        ssd_storage_->sync();
    }
}

std::optional<std::string> HybridCache::get(const std::string& key) {
    auto start_time = std::chrono::steady_clock::now();

    // Try memory cache first
    {
        std::shared_lock<std::shared_mutex> lock(memory_mutex_);
        auto it = memory_cache_.find(key);
        if (it != memory_cache_.end()) {
            // Check if expired
            if (std::chrono::steady_clock::now() < it->second.expiry_time) {
                // Update access time for LRU
                it->second.last_access = std::chrono::steady_clock::now();
                hit_count_++;
                update_get_latency(start_time);
                return it->second.value;
            } else {
                // Expired, remove from memory
                memory_usage_ -= it->second.value.size();
                memory_cache_.erase(it);
            }
        }
    }

    // Try SSD storage if available
    if (use_ssd_ && ssd_storage_) {
        try {
            auto result = ssd_storage_->read_async(key);
            if (result.has_value()) {
                // Update memory cache
                put_memory_cache(key, result.value(), config_.default_ttl);
                hit_count_++;
                update_get_latency(start_time);
                return result.value();
            }
        } catch (const std::exception& e) {
            std::cerr << "SSD read error: " << e.what() << std::endl;
        }
    }

    miss_count_++;
    update_get_latency(start_time);
    return std::nullopt;
}

bool HybridCache::put(const std::string& key, const std::string& value, 
                      std::chrono::seconds ttl) {
    auto start_time = std::chrono::steady_clock::now();

    // Use default TTL if not specified
    if (ttl.count() <= 0) {
        ttl = config_.default_ttl;
    }

    // Always try to put in memory cache first
    bool memory_success = put_memory_cache(key, value, ttl);

    // Write to SSD storage asynchronously if available
    if (use_ssd_ && ssd_storage_) {
        thread_pool_->enqueue([this, key, value, ttl]() {
            try {
                ssd_storage_->write_async(key, value, ttl);
            } catch (const std::exception& e) {
                std::cerr << "SSD write error: " << e.what() << std::endl;
            }
        });
    }

    update_put_latency(start_time);
    return memory_success || use_ssd_;
}

bool HybridCache::remove(const std::string& key) {
    auto start_time = std::chrono::steady_clock::now();

    bool removed = false;

    // Remove from memory cache
    {
        std::unique_lock<std::shared_mutex> lock(memory_mutex_);
        auto it = memory_cache_.find(key);
        if (it != memory_cache_.end()) {
            memory_usage_ -= it->second.value.size();
            memory_cache_.erase(it);
            removed = true;
        }
    }

    // Note: We don't remove from SSD storage as it's append-only
    // The entry will be ignored due to TTL or overwritten on next write

    update_remove_latency(start_time);
    return removed;
}

bool HybridCache::contains(const std::string& key) {
    // Check memory cache first
    {
        std::shared_lock<std::shared_mutex> lock(memory_mutex_);
        auto it = memory_cache_.find(key);
        if (it != memory_cache_.end()) {
            if (std::chrono::steady_clock::now() < it->second.expiry_time) {
                return true;
            }
        }
    }

    // Check SSD storage if available
    if (use_ssd_ && ssd_storage_) {
        try {
            auto result = ssd_storage_->read_async(key);
            return result.has_value();
        } catch (const std::exception& e) {
            std::cerr << "SSD contains error: " << e.what() << std::endl;
        }
    }

    return false;
}

void HybridCache::clear() {
    {
        std::unique_lock<std::shared_mutex> lock(memory_mutex_);
        memory_cache_.clear();
        memory_usage_ = 0;
    }

    // Note: We don't clear SSD storage as it would require recreating files
    // Entries will expire naturally based on TTL
}

CacheStats HybridCache::get_stats() const {
    CacheStats stats;
    stats.memory_hits = hit_count_.load();
    stats.memory_misses = miss_count_.load();
    stats.memory_entries = memory_cache_.size();
    stats.memory_usage = memory_usage_.load();
    stats.evictions = eviction_count_.load();
    stats.ssd_enabled = use_ssd_;
    
    if (ssd_storage_) {
        auto ssd_stats = ssd_storage_->get_stats();
        stats.ssd_reads = ssd_stats.reads.load();
        stats.ssd_writes = ssd_stats.writes.load();
        stats.ssd_errors = ssd_stats.errors.load();
    }
    
    return stats;
}

bool HybridCache::put_memory_cache(const std::string& key, const std::string& value, 
                                   std::chrono::seconds ttl) {
    std::unique_lock<std::shared_mutex> lock(memory_mutex_);

    // Check if we need to evict entries
    while (memory_cache_.size() >= config_.max_memory_entries || 
           memory_usage_ + value.size() > config_.max_memory_bytes) {
        if (!evict_lru_entry()) {
            break; // No more entries to evict
        }
    }

    // Check if we still have space
    if (memory_cache_.size() >= config_.max_memory_entries || 
        memory_usage_ + value.size() > config_.max_memory_bytes) {
        return false; // No space available
    }

    // Remove existing entry if present
    auto it = memory_cache_.find(key);
    if (it != memory_cache_.end()) {
        memory_usage_ -= it->second.value.size();
    }

    // Add new entry
    CacheEntry entry;
    entry.value = value;
    entry.last_access = std::chrono::steady_clock::now();
    entry.expiry_time = entry.last_access + ttl;

    memory_cache_[key] = std::move(entry);
    memory_usage_ += value.size();

    return true;
}

bool HybridCache::evict_lru_entry() {
    if (memory_cache_.empty()) {
        return false;
    }

    // Find LRU entry
    auto lru_it = memory_cache_.begin();
    auto oldest_time = lru_it->second.last_access;

    for (auto it = memory_cache_.begin(); it != memory_cache_.end(); ++it) {
        if (it->second.last_access < oldest_time) {
            oldest_time = it->second.last_access;
            lru_it = it;
        }
    }

    // Remove LRU entry
    memory_usage_ -= lru_it->second.value.size();
    memory_cache_.erase(lru_it);
    eviction_count_++;

    return true;
}

void HybridCache::cleanup_expired_entries() {
    std::unique_lock<std::shared_mutex> lock(memory_mutex_);
    
    auto now = std::chrono::steady_clock::now();
    auto it = memory_cache_.begin();
    
    while (it != memory_cache_.end()) {
        if (now >= it->second.expiry_time) {
            memory_usage_ -= it->second.value.size();
            it = memory_cache_.erase(it);
        } else {
            ++it;
        }
    }
}

void HybridCache::update_metrics() {
    // Update any additional metrics here
    // This could include histogram updates, etc.
}

void HybridCache::update_get_latency(std::chrono::steady_clock::time_point start) {
    auto duration = std::chrono::steady_clock::now() - start;
    // Update latency histogram if available
}

void HybridCache::update_put_latency(std::chrono::steady_clock::time_point start) {
    auto duration = std::chrono::steady_clock::now() - start;
    // Update latency histogram if available
}

void HybridCache::update_remove_latency(std::chrono::steady_clock::time_point start) {
    auto duration = std::chrono::steady_clock::now() - start;
    // Update latency histogram if available
}

} // namespace cache
} // namespace meteor 