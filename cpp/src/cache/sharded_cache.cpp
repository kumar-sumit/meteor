#include "../../include/cache/sharded_cache.hpp"
#include "../../include/utils/simd_utils.hpp"
#include <algorithm>

namespace meteor {
namespace cache {

// Thread-local shard hint
thread_local size_t ShardedCache::thread_shard_hint_ = 0;

CacheShard::CacheShard(size_t initial_capacity) 
    : capacity_(initial_capacity), size_(0), memory_usage_(0),
      hit_count_(0), miss_count_(0), eviction_count_(0) {
    buckets_ = std::make_unique<HashBucket[]>(capacity_);
    memory_pool_ = std::make_unique<utils::MemoryPool>(4096, 1000);
}

CacheShard::~CacheShard() = default;

bool CacheShard::get(const std::string& key, std::string& value) {
    size_t bucket_idx = find_bucket(key);
    auto* entry = buckets_[bucket_idx].entry.load(std::memory_order_acquire);
    
    if (entry && entry->key == key && !entry->is_expired()) {
        value = entry->value;
        entry->touch();
        hit_count_++;
        return true;
    }
    
    miss_count_++;
    return false;
}

bool CacheShard::put(const std::string& key, const std::string& value, std::chrono::milliseconds ttl) {
    size_t bucket_idx = find_bucket(key);
    auto entry = std::make_unique<CacheEntry>(key, value, ttl);
    
    if (try_insert(bucket_idx, std::move(entry))) {
        size_++;
        memory_usage_ += key.size() + value.size() + sizeof(CacheEntry);
        return true;
    }
    
    return try_update(bucket_idx, key, value, ttl);
}

bool CacheShard::remove(const std::string& key) {
    size_t bucket_idx = find_bucket(key);
    auto entry = try_remove(bucket_idx, key);
    
    if (entry) {
        size_--;
        memory_usage_ -= entry->memory_usage();
        return true;
    }
    
    return false;
}

bool CacheShard::contains(const std::string& key) {
    size_t bucket_idx = find_bucket(key);
    auto* entry = buckets_[bucket_idx].entry.load(std::memory_order_acquire);
    
    return entry && entry->key == key && !entry->is_expired();
}

void CacheShard::clear() {
    for (size_t i = 0; i < capacity_; ++i) {
        auto* entry = buckets_[i].entry.exchange(nullptr, std::memory_order_acq_rel);
        if (entry) {
            delete entry;
        }
    }
    size_ = 0;
    memory_usage_ = 0;
}

size_t CacheShard::hash_key(const std::string& key) const {
    return utils::simd_hash_xxhash(key.data(), key.size());
}

size_t CacheShard::find_bucket(const std::string& key) const {
    return hash_key(key) % capacity_;
}

bool CacheShard::try_insert(size_t bucket_idx, std::unique_ptr<CacheEntry> entry) {
    CacheEntry* expected = nullptr;
    CacheEntry* new_entry = entry.release();
    
    if (buckets_[bucket_idx].entry.compare_exchange_strong(expected, new_entry, std::memory_order_acq_rel)) {
        return true;
    }
    
    delete new_entry;
    return false;
}

bool CacheShard::try_update(size_t bucket_idx, const std::string& key, const std::string& value, std::chrono::milliseconds ttl) {
    auto* entry = buckets_[bucket_idx].entry.load(std::memory_order_acquire);
    
    if (entry && entry->key == key) {
        // Update existing entry
        entry->value = value;
        entry->touch();
        if (ttl.count() > 0) {
            entry->expires_at = std::chrono::steady_clock::now() + ttl;
            entry->has_ttl = true;
        }
        return true;
    }
    
    return false;
}

std::unique_ptr<CacheEntry> CacheShard::try_remove(size_t bucket_idx, const std::string& key) {
    auto* entry = buckets_[bucket_idx].entry.load(std::memory_order_acquire);
    
    if (entry && entry->key == key) {
        auto* removed = buckets_[bucket_idx].entry.exchange(nullptr, std::memory_order_acq_rel);
        if (removed) {
            return std::unique_ptr<CacheEntry>(removed);
        }
    }
    
    return nullptr;
}

// ShardedCache implementation
ShardedCache::ShardedCache(const CacheConfig& config) 
    : config_(config), running_(false) {
    
    shard_count_ = config_.shard_count;
    if (shard_count_ == 0) {
        shard_count_ = std::thread::hardware_concurrency();
    }
    
    // Ensure power of 2 for efficient modulo
    shard_count_ = 1ULL << static_cast<size_t>(std::log2(shard_count_));
    shard_mask_ = shard_count_ - 1;
    
    // Create shards
    for (size_t i = 0; i < shard_count_; ++i) {
        shards_.push_back(std::make_unique<CacheShard>(config_.max_entries / shard_count_));
    }
}

ShardedCache::~ShardedCache() {
    stop();
}

bool ShardedCache::get(const std::string& key, std::string& value) {
    size_t shard_idx = get_shard_index(key);
    return shards_[shard_idx]->get(key, value);
}

bool ShardedCache::put(const std::string& key, const std::string& value, std::chrono::milliseconds ttl) {
    size_t shard_idx = get_shard_index(key);
    return shards_[shard_idx]->put(key, value, ttl);
}

bool ShardedCache::remove(const std::string& key) {
    size_t shard_idx = get_shard_index(key);
    return shards_[shard_idx]->remove(key);
}

bool ShardedCache::contains(const std::string& key) {
    size_t shard_idx = get_shard_index(key);
    return shards_[shard_idx]->contains(key);
}

void ShardedCache::clear() {
    for (auto& shard : shards_) {
        shard->clear();
    }
}

CacheStats ShardedCache::get_stats() const {
    CacheStats stats{};
    
    for (const auto& shard : shards_) {
        stats.memory_entries += shard->size();
        stats.memory_usage += shard->memory_usage();
        stats.memory_hits += shard->get_hit_count();
        stats.memory_misses += shard->get_miss_count();
        stats.evictions += shard->get_eviction_count();
    }
    
    return stats;
}

size_t ShardedCache::size() const {
    size_t total = 0;
    for (const auto& shard : shards_) {
        total += shard->size();
    }
    return total;
}

size_t ShardedCache::memory_usage() const {
    size_t total = 0;
    for (const auto& shard : shards_) {
        total += shard->memory_usage();
    }
    return total;
}

void ShardedCache::start() {
    running_ = true;
    
    // Start maintenance thread
    maintenance_thread_ = std::thread([this]() {
        maintenance_loop();
    });
}

void ShardedCache::stop() {
    running_ = false;
    
    if (maintenance_thread_.joinable()) {
        maintenance_thread_.join();
    }
}

size_t ShardedCache::get_shard_index(const std::string& key) const {
    return fast_hash(key) & shard_mask_;
}

uint64_t ShardedCache::fast_hash(const std::string& key) const {
    return utils::simd_hash_xxhash(key.data(), key.size());
}

void ShardedCache::maintenance_loop() {
    while (running_) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        
        // Perform maintenance tasks
        for (auto& shard : shards_) {
            shard->evict_expired();
        }
    }
}

// Stub implementations for interface compatibility
bool ShardedCache::get(utils::span<const char> key, std::vector<char>& value) {
    std::string key_str(key.data(), key.size());
    std::string value_str;
    if (get(key_str, value_str)) {
        value.assign(value_str.begin(), value_str.end());
        return true;
    }
    return false;
}

bool ShardedCache::put(utils::span<const char> key, utils::span<const char> value, std::chrono::milliseconds ttl) {
    std::string key_str(key.data(), key.size());
    std::string value_str(value.data(), value.size());
    return put(key_str, value_str, ttl);
}

std::vector<std::optional<std::string>> ShardedCache::multi_get(const std::vector<std::string>& keys) {
    std::vector<std::optional<std::string>> results;
    results.reserve(keys.size());
    
    for (const auto& key : keys) {
        std::string value;
        if (get(key, value)) {
            results.emplace_back(std::move(value));
        } else {
            results.emplace_back(std::nullopt);
        }
    }
    
    return results;
}

bool ShardedCache::multi_put(const std::vector<std::pair<std::string, std::string>>& pairs, std::chrono::milliseconds ttl) {
    bool all_success = true;
    for (const auto& pair : pairs) {
        if (!put(pair.first, pair.second, ttl)) {
            all_success = false;
        }
    }
    return all_success;
}

bool ShardedCache::multi_remove(const std::vector<std::string>& keys) {
    bool all_success = true;
    for (const auto& key : keys) {
        if (!remove(key)) {
            all_success = false;
        }
    }
    return all_success;
}

void ShardedCache::set_max_memory(size_t bytes) {
    config_.max_memory_bytes = bytes;
}

void ShardedCache::set_max_entries(size_t count) {
    config_.max_entries = count;
}

void ShardedCache::set_default_ttl(std::chrono::milliseconds ttl) {
    config_.default_ttl = ttl;
}

void ShardedCache::flush() {
    clear();
}

bool ShardedCache::is_healthy() const {
    return running_;
}

} // namespace cache
} // namespace meteor 