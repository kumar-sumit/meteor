#pragma once

#include <memory>
#include <vector>
#include <atomic>
#include <mutex>
#include <cstddef>
#include <cstdint>
#include <string_view>

namespace meteor {
namespace utils {

// Simple span-like class for C++17 compatibility
template<typename T>
class span {
public:
    constexpr span() noexcept : data_(nullptr), size_(0) {}
    constexpr span(T* data, size_t size) noexcept : data_(data), size_(size) {}
    template<size_t N>
    constexpr span(T (&arr)[N]) noexcept : data_(arr), size_(N) {}
    
    constexpr T* data() const noexcept { return data_; }
    constexpr size_t size() const noexcept { return size_; }
    constexpr bool empty() const noexcept { return size_ == 0; }
    
    constexpr T& operator[](size_t idx) const { return data_[idx]; }
    constexpr T* begin() const noexcept { return data_; }
    constexpr T* end() const noexcept { return data_ + size_; }
    
private:
    T* data_;
    size_t size_;
};

// Memory pool for efficient allocation and zero-copy operations
template<typename T>
class MemoryPool {
public:
    explicit MemoryPool(size_t block_size = 1024, size_t initial_blocks = 16);
    ~MemoryPool();
    
    // Non-copyable, non-movable
    MemoryPool(const MemoryPool&) = delete;
    MemoryPool& operator=(const MemoryPool&) = delete;
    MemoryPool(MemoryPool&&) = delete;
    MemoryPool& operator=(MemoryPool&&) = delete;
    
    // Allocate and deallocate
    T* allocate(size_t count = 1);
    void deallocate(T* ptr, size_t count = 1);
    
    // Pool statistics
    size_t get_allocated_blocks() const { return allocated_blocks_.load(); }
    size_t get_free_blocks() const { return free_blocks_.load(); }
    size_t get_total_blocks() const { return total_blocks_.load(); }
    
    // Pool management
    void expand(size_t additional_blocks);
    void shrink();
    void clear();
    
private:
    struct Block {
        alignas(T) char data[sizeof(T)];
        Block* next = nullptr;
    };
    
    mutable std::mutex mutex_;
    std::vector<std::unique_ptr<Block[]>> chunks_;
    Block* free_list_ = nullptr;
    
    size_t block_size_;
    std::atomic<size_t> allocated_blocks_{0};
    std::atomic<size_t> free_blocks_{0};
    std::atomic<size_t> total_blocks_{0};
    
    void allocate_chunk(size_t num_blocks);
};

// Buffer pool for zero-copy operations
class BufferPool {
public:
    explicit BufferPool(size_t small_size = 1024, size_t medium_size = 8192, size_t large_size = 65536);
    ~BufferPool();
    
    // Buffer allocation
    span<char> allocate(size_t size);
    void deallocate(span<char> buffer);
    
    // Pool statistics
    size_t get_small_allocated() const { return small_allocated_.load(); }
    size_t get_medium_allocated() const { return medium_allocated_.load(); }
    size_t get_large_allocated() const { return large_allocated_.load(); }
    
private:
    MemoryPool<char> small_pool_;
    MemoryPool<char> medium_pool_;
    MemoryPool<char> large_pool_;
    
    size_t small_size_;
    size_t medium_size_;
    size_t large_size_;
    
    std::atomic<size_t> small_allocated_{0};
    std::atomic<size_t> medium_allocated_{0};
    std::atomic<size_t> large_allocated_{0};
};

// Zero-copy string view with lifetime management
class ZeroCopyStringView {
public:
    ZeroCopyStringView() = default;
    ZeroCopyStringView(const char* data, size_t size, std::shared_ptr<void> lifetime_manager = nullptr);
    ZeroCopyStringView(span<const char> data, std::shared_ptr<void> lifetime_manager = nullptr);
    
    // String view interface
    const char* data() const { return data_; }
    size_t size() const { return size_; }
    bool empty() const { return size_ == 0; }
    
    // Conversion
    std::string to_string() const { return std::string(data_, size_); }
    span<const char> to_span() const { return span<const char>(data_, size_); }
    
    // Comparison
    bool operator==(const ZeroCopyStringView& other) const;
    bool operator==(const std::string& other) const;
    bool operator==(std::string_view other) const;
    
private:
    const char* data_ = nullptr;
    size_t size_ = 0;
    std::shared_ptr<void> lifetime_manager_;
};

// Template implementation
template<typename T>
MemoryPool<T>::MemoryPool(size_t block_size, size_t initial_blocks)
    : block_size_(block_size) {
    allocate_chunk(initial_blocks);
}

template<typename T>
MemoryPool<T>::~MemoryPool() {
    clear();
}

template<typename T>
T* MemoryPool<T>::allocate(size_t count) {
    if (count != 1) {
        // For now, only support single object allocation
        return static_cast<T*>(std::malloc(count * sizeof(T)));
    }
    
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (!free_list_) {
        allocate_chunk(block_size_);
    }
    
    Block* block = free_list_;
    free_list_ = free_list_->next;
    
    allocated_blocks_.fetch_add(1);
    free_blocks_.fetch_sub(1);
    
    return reinterpret_cast<T*>(block);
}

template<typename T>
void MemoryPool<T>::deallocate(T* ptr, size_t count) {
    if (count != 1) {
        std::free(ptr);
        return;
    }
    
    std::lock_guard<std::mutex> lock(mutex_);
    
    Block* block = reinterpret_cast<Block*>(ptr);
    block->next = free_list_;
    free_list_ = block;
    
    allocated_blocks_.fetch_sub(1);
    free_blocks_.fetch_add(1);
}

template<typename T>
void MemoryPool<T>::allocate_chunk(size_t num_blocks) {
    auto chunk = std::make_unique<Block[]>(num_blocks);
    
    // Link blocks in free list
    for (size_t i = 0; i < num_blocks - 1; ++i) {
        chunk[i].next = &chunk[i + 1];
    }
    chunk[num_blocks - 1].next = free_list_;
    free_list_ = &chunk[0];
    
    chunks_.push_back(std::move(chunk));
    
    free_blocks_.fetch_add(num_blocks);
    total_blocks_.fetch_add(num_blocks);
}

template<typename T>
void MemoryPool<T>::expand(size_t additional_blocks) {
    std::lock_guard<std::mutex> lock(mutex_);
    allocate_chunk(additional_blocks);
}

template<typename T>
void MemoryPool<T>::shrink() {
    std::lock_guard<std::mutex> lock(mutex_);
    // Implementation for shrinking would be complex
    // For now, just clear unused chunks
}

template<typename T>
void MemoryPool<T>::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    chunks_.clear();
    free_list_ = nullptr;
    allocated_blocks_.store(0);
    free_blocks_.store(0);
    total_blocks_.store(0);
}

} // namespace utils
} // namespace meteor 