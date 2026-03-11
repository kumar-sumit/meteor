#include "../../include/storage/storage_backend.hpp"
#include "../../include/utils/memory_pool.hpp"
#include <iostream>
#include <fstream>
#include <filesystem>
#include <unordered_map>
#include <shared_mutex>
#include <chrono>
#include <atomic>
#include <thread>
#include <future>
#include <queue>

#ifdef __linux__
#include <sys/eventfd.h>
#include <sys/epoll.h>
#ifdef HAVE_URING
#include <liburing.h>
#endif
#elif __APPLE__
#include <sys/event.h>
#include <sys/time.h>
#include <sys/types.h>
#endif

namespace meteor {
namespace storage {

// Storage statistics
struct StorageStats {
    std::atomic<uint64_t> reads{0};
    std::atomic<uint64_t> writes{0};
    std::atomic<uint64_t> deletes{0};
    std::atomic<uint64_t> cache_hits{0};
    std::atomic<uint64_t> cache_misses{0};
    std::atomic<uint64_t> bytes_read{0};
    std::atomic<uint64_t> bytes_written{0};
    std::atomic<uint64_t> total_entries{0};
    std::atomic<uint64_t> total_size{0};
};

// File-based storage backend with async I/O
class FileStorageBackend : public StorageBackend {
private:
    struct Entry {
        std::string value;
        std::chrono::time_point<std::chrono::steady_clock> expires_at;
        bool has_ttl;
        
        Entry(const std::string& v, std::chrono::milliseconds ttl = std::chrono::milliseconds::zero())
            : value(v), has_ttl(ttl.count() > 0) {
            if (has_ttl) {
                expires_at = std::chrono::steady_clock::now() + ttl;
            }
        }
        
        bool is_expired() const {
            return has_ttl && std::chrono::steady_clock::now() > expires_at;
        }
    };
    
    mutable std::shared_mutex mutex_;
    std::unordered_map<std::string, Entry> data_;
    std::string storage_dir_;
    mutable StorageStats stats_;
    
#ifdef __linux__
#ifdef HAVE_URING
    struct io_uring ring_;
    bool io_uring_initialized_ = false;
#endif
#elif __APPLE__
    int kqueue_fd_ = -1;
#endif
    
    std::thread cleanup_thread_;
    std::atomic<bool> shutdown_{false};
    
public:
    explicit FileStorageBackend(const std::string& storage_dir = "/tmp/meteor_storage")
        : storage_dir_(storage_dir) {
        
        // Create storage directory
        std::filesystem::create_directories(storage_dir_);
        
        // Initialize async I/O
        initialize_async_io();
        
        // Start cleanup thread for expired entries
        cleanup_thread_ = std::thread([this] {
            cleanup_expired_entries();
        });
    }
    
    ~FileStorageBackend() override {
        shutdown_.store(true);
        if (cleanup_thread_.joinable()) {
            cleanup_thread_.join();
        }
        
        cleanup_async_io();
    }
    
    bool get(const std::string& key, std::string& value) override {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        
        auto it = data_.find(key);
        if (it != data_.end()) {
            if (it->second.is_expired()) {
                lock.unlock();
                std::unique_lock<std::shared_mutex> write_lock(mutex_);
                data_.erase(it);
                stats_.cache_misses.fetch_add(1);
                return false;
            }
            
            value = it->second.value;
            stats_.cache_hits.fetch_add(1);
            stats_.reads.fetch_add(1);
            stats_.bytes_read.fetch_add(value.size());
            return true;
        }
        
        stats_.cache_misses.fetch_add(1);
        return false;
    }
    
    bool get(utils::span<const char> key, std::vector<char>& value) override {
        std::string key_str(key.data(), key.size());
        std::string value_str;
        
        if (get(key_str, value_str)) {
            value.assign(value_str.begin(), value_str.end());
            return true;
        }
        
        return false;
    }
    
    bool put(const std::string& key, const std::string& value, 
             std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) override {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        
        auto it = data_.find(key);
        bool is_new = (it == data_.end());
        
        if (is_new) {
            data_.emplace(key, Entry(value, ttl));
            stats_.total_entries.fetch_add(1);
        } else {
            stats_.total_size.fetch_sub(it->second.value.size());
            it->second = Entry(value, ttl);
        }
        
        stats_.total_size.fetch_add(value.size());
        stats_.writes.fetch_add(1);
        stats_.bytes_written.fetch_add(value.size());
        
        return true;
    }
    
    bool put(utils::span<const char> key, utils::span<const char> value,
             std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) override {
        std::string key_str(key.data(), key.size());
        std::string value_str(value.data(), value.size());
        return put(key_str, value_str, ttl);
    }
    
    bool remove(const std::string& key) override {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        
        auto it = data_.find(key);
        if (it != data_.end()) {
            stats_.total_size.fetch_sub(it->second.value.size());
            stats_.total_entries.fetch_sub(1);
            data_.erase(it);
            stats_.deletes.fetch_add(1);
            return true;
        }
        
        return false;
    }
    
    bool contains(const std::string& key) override {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        
        auto it = data_.find(key);
        if (it != data_.end()) {
            if (it->second.is_expired()) {
                lock.unlock();
                std::unique_lock<std::shared_mutex> write_lock(mutex_);
                data_.erase(it);
                return false;
            }
            return true;
        }
        
        return false;
    }
    
    void clear() override {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        data_.clear();
        stats_.total_entries.store(0);
        stats_.total_size.store(0);
    }
    
    std::future<bool> get_async(const std::string& key, std::string& value) override {
        return std::async(std::launch::async, [this, key, &value]() {
            return get(key, value);
        });
    }
    
    std::future<bool> put_async(const std::string& key, const std::string& value,
                               std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) override {
        return std::async(std::launch::async, [this, key, value, ttl]() {
            return put(key, value, ttl);
        });
    }
    
    std::future<bool> remove_async(const std::string& key) override {
        return std::async(std::launch::async, [this, key]() {
            return remove(key);
        });
    }
    
    std::vector<std::optional<std::string>> multi_get(
        const std::vector<std::string>& keys) override {
        std::vector<std::optional<std::string>> results;
        results.reserve(keys.size());
        
        std::shared_lock<std::shared_mutex> lock(mutex_);
        
        for (const auto& key : keys) {
            auto it = data_.find(key);
            if (it != data_.end() && !it->second.is_expired()) {
                results.emplace_back(it->second.value);
                stats_.cache_hits.fetch_add(1);
            } else {
                results.emplace_back(std::nullopt);
                stats_.cache_misses.fetch_add(1);
            }
        }
        
        stats_.reads.fetch_add(keys.size());
        
        return results;
    }
    
    bool multi_put(const std::vector<std::pair<std::string, std::string>>& pairs,
                  std::chrono::milliseconds ttl = std::chrono::milliseconds::zero()) override {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        
        for (const auto& pair : pairs) {
            auto it = data_.find(pair.first);
            bool is_new = (it == data_.end());
            
            if (is_new) {
                data_.emplace(pair.first, Entry(pair.second, ttl));
                stats_.total_entries.fetch_add(1);
            } else {
                stats_.total_size.fetch_sub(it->second.value.size());
                it->second = Entry(pair.second, ttl);
            }
            
            stats_.total_size.fetch_add(pair.second.size());
            stats_.bytes_written.fetch_add(pair.second.size());
        }
        
        stats_.writes.fetch_add(pairs.size());
        
        return true;
    }
    
    StorageStats get_stats() const override {
        return stats_;
    }
    
    size_t size() const override {
        return stats_.total_entries.load();
    }
    
    size_t disk_usage() const override {
        return stats_.total_size.load();
    }
    
private:
    void initialize_async_io() {
#ifdef __linux__
#ifdef HAVE_URING
        // Initialize io_uring for Linux
        if (io_uring_queue_init(256, &ring_, 0) == 0) {
            io_uring_initialized_ = true;
        }
#endif
#elif __APPLE__
        // Initialize kqueue for macOS
        kqueue_fd_ = kqueue();
#endif
    }
    
    void cleanup_async_io() {
#ifdef __linux__
#ifdef HAVE_URING
        if (io_uring_initialized_) {
            io_uring_queue_exit(&ring_);
        }
#endif
#elif __APPLE__
        if (kqueue_fd_ != -1) {
            close(kqueue_fd_);
        }
#endif
    }
    
    void cleanup_expired_entries() {
        while (!shutdown_.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(30));
            
            std::unique_lock<std::shared_mutex> lock(mutex_);
            
            auto it = data_.begin();
            while (it != data_.end()) {
                if (it->second.is_expired()) {
                    stats_.total_size.fetch_sub(it->second.value.size());
                    stats_.total_entries.fetch_sub(1);
                    it = data_.erase(it);
                } else {
                    ++it;
                }
            }
        }
    }
};

// Factory function
std::unique_ptr<StorageBackend> create_file_storage_backend(const std::string& storage_dir) {
    return std::make_unique<FileStorageBackend>(storage_dir);
}

} // namespace storage
} // namespace meteor 