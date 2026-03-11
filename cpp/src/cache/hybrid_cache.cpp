#include "../../include/cache/hybrid_cache.hpp"
#include "../../include/storage/storage_backend.hpp"
#include <algorithm>
#include <chrono>
#include <thread>
#include <iostream>
#include <filesystem>
#include <fstream>

namespace meteor {
namespace cache {

HybridCache::HybridCache(const CacheConfig& config) : config_(config), running_(false) {
    if (!config_.tiered_storage_prefix.empty()) {
        std::filesystem::create_directories(config_.tiered_storage_prefix);
    }
}

HybridCache::~HybridCache() {
    stop();
}

bool HybridCache::get(const std::string& key, std::string& value) {
    // Try memory cache first
    std::lock_guard<std::mutex> lock(mutex_);
    
    auto it = memory_cache_.find(key);
    if (it != memory_cache_.end() && !it->second.is_expired()) {
        value = it->second.value;
        const_cast<CacheEntry&>(it->second).touch();
        stats_.memory_hits++;
        return true;
    }
    
    // Try SSD cache if enabled
    if (!config_.tiered_storage_prefix.empty()) {
        std::string ssd_path = get_ssd_path(key);
        std::ifstream file(ssd_path, std::ios::binary);
        if (file.is_open()) {
            std::string ssd_value((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
            if (!ssd_value.empty()) {
                value = ssd_value;
                
                // Promote to memory cache
                if (memory_cache_.size() < config_.max_memory_entries) {
                    CacheEntry entry;
                    entry.key = key;
                    entry.value = value;
                    entry.created_at = std::chrono::steady_clock::now();
                    entry.last_accessed = std::chrono::steady_clock::now();
                    memory_cache_[key] = entry;
                }
                
                stats_.ssd_hits++;
                return true;
            }
        }
    }
    
    stats_.memory_misses++;
    return false;
}

bool HybridCache::put(const std::string& key, const std::string& value, std::chrono::milliseconds ttl) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    // Try to put in memory cache first
    if (memory_cache_.size() < config_.max_memory_entries) {
        CacheEntry entry;
        entry.key = key;
        entry.value = value;
        entry.created_at = std::chrono::steady_clock::now();
        entry.last_accessed = std::chrono::steady_clock::now();
        
        if (ttl.count() > 0) {
            entry.has_ttl = true;
            entry.expires_at = std::chrono::steady_clock::now() + ttl;
        }
        
        memory_cache_[key] = entry;
        stats_.puts++;
        return true;
    }
    
    // Overflow to SSD if enabled
    if (!config_.tiered_storage_prefix.empty()) {
        std::string ssd_path = get_ssd_path(key);
        std::filesystem::create_directories(std::filesystem::path(ssd_path).parent_path());
        
        std::ofstream file(ssd_path, std::ios::binary);
        if (file.is_open()) {
            file.write(value.data(), value.size());
            file.close();
            stats_.puts++;
            return true;
        }
    }
    
    return false;
}

bool HybridCache::remove(const std::string& key) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    bool removed = false;
    
    // Remove from memory cache
    if (memory_cache_.erase(key) > 0) {
        removed = true;
    }
    
    // Remove from SSD cache
    if (!config_.tiered_storage_prefix.empty()) {
        std::string ssd_path = get_ssd_path(key);
        if (std::filesystem::exists(ssd_path)) {
            std::filesystem::remove(ssd_path);
            removed = true;
        }
    }
    
    if (removed) {
        stats_.removes++;
    }
    
    return removed;
}

bool HybridCache::contains(const std::string& key) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    // Check memory cache
    auto it = memory_cache_.find(key);
    if (it != memory_cache_.end() && !it->second.is_expired()) {
        return true;
    }
    
    // Check SSD cache
    if (!config_.tiered_storage_prefix.empty()) {
        std::string ssd_path = get_ssd_path(key);
        return std::filesystem::exists(ssd_path);
    }
    
    return false;
}

void HybridCache::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    memory_cache_.clear();
    
    if (!config_.tiered_storage_prefix.empty()) {
        std::filesystem::remove_all(config_.tiered_storage_prefix);
        std::filesystem::create_directories(config_.tiered_storage_prefix);
    }
}

CacheStats HybridCache::get_stats() const {
    std::lock_guard<std::mutex> lock(mutex_);
    
    CacheStats stats = stats_;
    stats.memory_entries = memory_cache_.size();
    
    size_t memory_bytes = 0;
    for (const auto& pair : memory_cache_) {
        memory_bytes += pair.second.memory_usage();
    }
    stats.memory_bytes = memory_bytes;
    
    return stats;
}

size_t HybridCache::size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return memory_cache_.size();
}

size_t HybridCache::memory_usage() const {
    std::lock_guard<std::mutex> lock(mutex_);
    
    size_t total = 0;
    for (const auto& pair : memory_cache_) {
        total += pair.second.memory_usage();
    }
    return total;
}

void HybridCache::start() {
    running_ = true;
}

void HybridCache::stop() {
    running_ = false;
}

std::string HybridCache::get_ssd_path(const std::string& key) const {
    std::hash<std::string> hasher;
    auto hash = hasher(key);
    return config_.tiered_storage_prefix + "/" + std::to_string(hash % 1000) + "/" + key;
}

// Stub implementations for interface compatibility
bool HybridCache::get(utils::span<const char> key, std::vector<char>& value) {
    std::string key_str(key.data(), key.size());
    std::string value_str;
    if (get(key_str, value_str)) {
        value.assign(value_str.begin(), value_str.end());
        return true;
    }
    return false;
}

bool HybridCache::put(utils::span<const char> key, utils::span<const char> value, std::chrono::milliseconds ttl) {
    std::string key_str(key.data(), key.size());
    std::string value_str(value.data(), value.size());
    return put(key_str, value_str, ttl);
}

std::vector<std::optional<std::string>> HybridCache::multi_get(const std::vector<std::string>& keys) {
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

bool HybridCache::multi_put(const std::vector<std::pair<std::string, std::string>>& pairs, std::chrono::milliseconds ttl) {
    bool all_success = true;
    for (const auto& pair : pairs) {
        if (!put(pair.first, pair.second, ttl)) {
            all_success = false;
        }
    }
    return all_success;
}

bool HybridCache::multi_remove(const std::vector<std::string>& keys) {
    bool all_success = true;
    for (const auto& key : keys) {
        if (!remove(key)) {
            all_success = false;
        }
    }
    return all_success;
}

void HybridCache::set_max_memory(size_t bytes) {
    config_.max_memory_bytes = bytes;
}

void HybridCache::set_max_entries(size_t count) {
    config_.max_memory_entries = count;
}

void HybridCache::set_default_ttl(std::chrono::milliseconds ttl) {
    config_.default_ttl = ttl;
}

void HybridCache::flush() {
    clear();
}

bool HybridCache::is_healthy() const {
    return running_;
}

} // namespace cache
} // namespace meteor 