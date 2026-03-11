#include "meteor/utils/memory_pool.hpp"
#include <algorithm>
#include <cstring>
#include <iostream>

namespace meteor {
namespace utils {

MemoryPool::MemoryPool(size_t initial_size, size_t max_size)
    : max_size_(max_size)
    , current_size_(0)
    , total_allocations_(0)
    , total_deallocations_(0)
    , peak_usage_(0)
{
    // Pre-allocate initial buffers
    for (size_t i = 0; i < initial_size; ++i) {
        auto buffer = std::make_unique<Buffer>();
        buffer->data.resize(DEFAULT_BUFFER_SIZE);
        available_buffers_.push(std::move(buffer));
        current_size_++;
    }
}

MemoryPool::~MemoryPool() {
    // Clean up all buffers
    while (!available_buffers_.empty()) {
        available_buffers_.pop();
    }
}

std::unique_ptr<Buffer> MemoryPool::get_buffer(size_t size) {
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    total_allocations_++;
    
    // Try to get from pool
    if (!available_buffers_.empty()) {
        auto buffer = std::move(available_buffers_.front());
        available_buffers_.pop();
        current_size_--;
        
        // Resize if needed
        if (buffer->data.size() < size) {
            buffer->data.resize(size);
        }
        
        buffer->used_size = size;
        return buffer;
    }
    
    // Create new buffer if pool is empty
    auto buffer = std::make_unique<Buffer>();
    buffer->data.resize(std::max(size, DEFAULT_BUFFER_SIZE));
    buffer->used_size = size;
    
    return buffer;
}

void MemoryPool::return_buffer(std::unique_ptr<Buffer> buffer) {
    if (!buffer) {
        return;
    }
    
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    total_deallocations_++;
    
    // Return to pool if not at capacity
    if (current_size_ < max_size_) {
        buffer->used_size = 0;
        available_buffers_.push(std::move(buffer));
        current_size_++;
        
        // Update peak usage
        peak_usage_ = std::max(peak_usage_, current_size_);
    }
    // Otherwise, buffer will be automatically destroyed
}

MemoryPoolStats MemoryPool::get_stats() const {
    std::shared_lock<std::shared_mutex> lock(pool_stats_mutex_);
    return {
        current_size_.load(),
        max_size_,
        total_allocations_.load(),
        total_deallocations_.load(),
        peak_usage_.load()
    };
}

void MemoryPool::clear() {
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    while (!available_buffers_.empty()) {
        available_buffers_.pop();
    }
    
    current_size_ = 0;
}

// BufferPool implementation
BufferPool::BufferPool(size_t buffer_size, size_t pool_size)
    : buffer_size_(buffer_size)
    , pool_size_(pool_size)
    , current_count_(0)
{
    // Pre-allocate aligned buffers
    for (size_t i = 0; i < pool_size; ++i) {
        auto buffer = allocate_aligned_buffer(buffer_size_);
        available_buffers_.push(buffer);
        current_count_++;
    }
}

BufferPool::~BufferPool() {
    // Clean up all buffers
    while (!available_buffers_.empty()) {
        auto buffer = available_buffers_.front();
        available_buffers_.pop();
        free_aligned_buffer(buffer);
    }
}

std::shared_ptr<uint8_t[]> BufferPool::get_buffer() {
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    if (!available_buffers_.empty()) {
        auto buffer = available_buffers_.front();
        available_buffers_.pop();
        current_count_--;
        
        // Wrap in shared_ptr with custom deleter
        return std::shared_ptr<uint8_t[]>(buffer, [this](uint8_t* ptr) {
            return_buffer(ptr);
        });
    }
    
    // Allocate new buffer if pool is empty
    auto buffer = allocate_aligned_buffer(buffer_size_);
    return std::shared_ptr<uint8_t[]>(buffer, [this](uint8_t* ptr) {
        return_buffer(ptr);
    });
}

void BufferPool::return_buffer(uint8_t* buffer) {
    if (!buffer) {
        return;
    }
    
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    // Return to pool if not at capacity
    if (current_count_ < pool_size_) {
        available_buffers_.push(buffer);
        current_count_++;
    } else {
        // Pool is full, free the buffer
        free_aligned_buffer(buffer);
    }
}

uint8_t* BufferPool::allocate_aligned_buffer(size_t size) {
    // Allocate aligned memory for O_DIRECT compatibility
    void* ptr = nullptr;
    
#ifdef _WIN32
    ptr = _aligned_malloc(size, 4096);
#else
    if (posix_memalign(&ptr, 4096, size) != 0) {
        throw std::bad_alloc();
    }
#endif
    
    if (!ptr) {
        throw std::bad_alloc();
    }
    
    return static_cast<uint8_t*>(ptr);
}

void BufferPool::free_aligned_buffer(uint8_t* buffer) {
#ifdef _WIN32
    _aligned_free(buffer);
#else
    free(buffer);
#endif
}

BufferPoolStats BufferPool::get_stats() const {
    std::shared_lock<std::shared_mutex> lock(pool_stats_mutex_);
    return {
        current_count_.load(),
        pool_size_,
        buffer_size_
    };
}

// ObjectPool implementation
template<typename T>
ObjectPool<T>::ObjectPool(size_t initial_size, size_t max_size)
    : max_size_(max_size)
    , current_size_(0)
    , total_created_(0)
    , total_reused_(0)
{
    // Pre-allocate objects
    for (size_t i = 0; i < initial_size; ++i) {
        available_objects_.push(std::make_unique<T>());
        current_size_++;
    }
}

template<typename T>
ObjectPool<T>::~ObjectPool() {
    while (!available_objects_.empty()) {
        available_objects_.pop();
    }
}

template<typename T>
std::unique_ptr<T> ObjectPool<T>::get_object() {
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    if (!available_objects_.empty()) {
        auto obj = std::move(available_objects_.front());
        available_objects_.pop();
        current_size_--;
        total_reused_++;
        return obj;
    }
    
    // Create new object if pool is empty
    total_created_++;
    return std::make_unique<T>();
}

template<typename T>
void ObjectPool<T>::return_object(std::unique_ptr<T> obj) {
    if (!obj) {
        return;
    }
    
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    // Return to pool if not at capacity
    if (current_size_ < max_size_) {
        available_objects_.push(std::move(obj));
        current_size_++;
    }
    // Otherwise, object will be automatically destroyed
}

template<typename T>
ObjectPoolStats ObjectPool<T>::get_stats() const {
    std::shared_lock<std::shared_mutex> lock(pool_stats_mutex_);
    return {
        current_size_.load(),
        max_size_,
        total_created_.load(),
        total_reused_.load()
    };
}

template<typename T>
void ObjectPool<T>::clear() {
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    while (!available_objects_.empty()) {
        available_objects_.pop();
    }
    
    current_size_ = 0;
}

// Explicit template instantiations for commonly used types
template class ObjectPool<std::string>;
template class ObjectPool<std::vector<char>>;

} // namespace utils
} // namespace meteor 