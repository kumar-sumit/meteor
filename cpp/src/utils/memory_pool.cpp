#include "../../include/utils/memory_pool.hpp"
#include <algorithm>
#include <cstring>

namespace meteor {
namespace utils {

// BufferPool implementation
BufferPool::BufferPool(size_t small_size, size_t medium_size, size_t large_size)
    : small_pool_(small_size, 64)
    , medium_pool_(medium_size, 32)
    , large_pool_(large_size, 16)
    , small_size_(small_size)
    , medium_size_(medium_size)
    , large_size_(large_size) {
}

BufferPool::~BufferPool() = default;

span<char> BufferPool::allocate(size_t size) {
    if (size <= small_size_) {
        char* ptr = small_pool_.allocate(small_size_);
        small_allocated_.fetch_add(1);
        return span<char>(ptr, small_size_);
    } else if (size <= medium_size_) {
        char* ptr = medium_pool_.allocate(medium_size_);
        medium_allocated_.fetch_add(1);
        return span<char>(ptr, medium_size_);
    } else if (size <= large_size_) {
        char* ptr = large_pool_.allocate(large_size_);
        large_allocated_.fetch_add(1);
        return span<char>(ptr, large_size_);
    } else {
        // For very large allocations, use regular malloc
        char* ptr = static_cast<char*>(std::malloc(size));
        return span<char>(ptr, size);
    }
}

void BufferPool::deallocate(span<char> buffer) {
    if (buffer.size() == small_size_) {
        small_pool_.deallocate(buffer.data(), small_size_);
        small_allocated_.fetch_sub(1);
    } else if (buffer.size() == medium_size_) {
        medium_pool_.deallocate(buffer.data(), medium_size_);
        medium_allocated_.fetch_sub(1);
    } else if (buffer.size() == large_size_) {
        large_pool_.deallocate(buffer.data(), large_size_);
        large_allocated_.fetch_sub(1);
    } else {
        // Free regular malloc allocation
        std::free(buffer.data());
    }
}

// ZeroCopyStringView implementation
ZeroCopyStringView::ZeroCopyStringView(const char* data, size_t size, std::shared_ptr<void> lifetime_manager)
    : data_(data), size_(size), lifetime_manager_(std::move(lifetime_manager)) {
}

ZeroCopyStringView::ZeroCopyStringView(span<const char> data, std::shared_ptr<void> lifetime_manager)
    : data_(data.data()), size_(data.size()), lifetime_manager_(std::move(lifetime_manager)) {
}

bool ZeroCopyStringView::operator==(const ZeroCopyStringView& other) const {
    return size_ == other.size_ && std::memcmp(data_, other.data_, size_) == 0;
}

bool ZeroCopyStringView::operator==(const std::string& other) const {
    return size_ == other.size() && std::memcmp(data_, other.data(), size_) == 0;
}

bool ZeroCopyStringView::operator==(std::string_view other) const {
    return size_ == other.size() && std::memcmp(data_, other.data(), size_) == 0;
}

} // namespace utils
} // namespace meteor 