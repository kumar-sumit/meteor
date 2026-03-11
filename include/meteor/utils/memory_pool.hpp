#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <queue>
#include <shared_mutex>
#include <vector>

#ifdef _WIN32
#include <malloc.h>
#else
#include <cstdlib>
#endif

namespace meteor {
namespace utils {

constexpr size_t DEFAULT_BUFFER_SIZE = 65536; // 64KB

struct Buffer {
    std::vector<uint8_t> data;
    size_t used_size = 0;
    std::chrono::steady_clock::time_point last_used;
    
    Buffer() = default;
    Buffer(const Buffer&) = delete;
    Buffer& operator=(const Buffer&) = delete;
    Buffer(Buffer&&) = default;
    Buffer& operator=(Buffer&&) = default;
};

struct MemoryPoolStats {
    size_t current_size;
    size_t max_size;
    uint64_t total_allocations;
    uint64_t total_deallocations;
    size_t peak_usage;
};

class MemoryPool {
public:
    MemoryPool(size_t initial_size = 64, size_t max_size = 1024);
    ~MemoryPool();

    // Disable copy and move
    MemoryPool(const MemoryPool&) = delete;
    MemoryPool& operator=(const MemoryPool&) = delete;
    MemoryPool(MemoryPool&&) = delete;
    MemoryPool& operator=(MemoryPool&&) = delete;

    // Get a buffer from the pool
    std::unique_ptr<Buffer> get_buffer(size_t size = DEFAULT_BUFFER_SIZE);
    
    // Return a buffer to the pool
    void return_buffer(std::unique_ptr<Buffer> buffer);
    
    // Get statistics
    MemoryPoolStats get_stats() const;
    
    // Clear the pool
    void clear();

private:
    std::queue<std::unique_ptr<Buffer>> available_buffers_;
    std::mutex pool_mutex_;
    mutable std::shared_mutex pool_stats_mutex_;
    
    size_t max_size_;
    std::atomic<size_t> current_size_;
    std::atomic<uint64_t> total_allocations_;
    std::atomic<uint64_t> total_deallocations_;
    std::atomic<size_t> peak_usage_;
};

struct BufferPoolStats {
    size_t current_count;
    size_t pool_size;
    size_t buffer_size;
};

class BufferPool {
public:
    BufferPool(size_t buffer_size, size_t pool_size);
    ~BufferPool();

    // Disable copy and move
    BufferPool(const BufferPool&) = delete;
    BufferPool& operator=(const BufferPool&) = delete;
    BufferPool(BufferPool&&) = delete;
    BufferPool& operator=(BufferPool&&) = delete;

    // Get an aligned buffer
    std::shared_ptr<uint8_t[]> get_buffer();
    
    // Get statistics
    BufferPoolStats get_stats() const;

private:
    size_t buffer_size_;
    size_t pool_size_;
    std::queue<uint8_t*> available_buffers_;
    std::mutex pool_mutex_;
    mutable std::shared_mutex pool_stats_mutex_;
    std::atomic<size_t> current_count_;
    
    void return_buffer(uint8_t* buffer);
    uint8_t* allocate_aligned_buffer(size_t size);
    void free_aligned_buffer(uint8_t* buffer);
};

struct ObjectPoolStats {
    size_t current_size;
    size_t max_size;
    uint64_t total_created;
    uint64_t total_reused;
};

template<typename T>
class ObjectPool {
public:
    ObjectPool(size_t initial_size = 16, size_t max_size = 256);
    ~ObjectPool();

    // Disable copy and move
    ObjectPool(const ObjectPool&) = delete;
    ObjectPool& operator=(const ObjectPool&) = delete;
    ObjectPool(ObjectPool&&) = delete;
    ObjectPool& operator=(ObjectPool&&) = delete;

    // Get an object from the pool
    std::unique_ptr<T> get_object();
    
    // Return an object to the pool
    void return_object(std::unique_ptr<T> obj);
    
    // Get statistics
    ObjectPoolStats get_stats() const;
    
    // Clear the pool
    void clear();

private:
    std::queue<std::unique_ptr<T>> available_objects_;
    std::mutex pool_mutex_;
    mutable std::shared_mutex pool_stats_mutex_;
    
    size_t max_size_;
    std::atomic<size_t> current_size_;
    std::atomic<uint64_t> total_created_;
    std::atomic<uint64_t> total_reused_;
};

// Explicit template instantiations for commonly used types
extern template class ObjectPool<std::string>;
extern template class ObjectPool<std::vector<char>>;

} // namespace utils
} // namespace meteor 