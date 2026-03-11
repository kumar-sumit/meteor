#pragma once

#include <cstddef>
#include <memory>

#ifdef _WIN32
#include <malloc.h>
#else
#include <cstdlib>
#endif

namespace meteor {
namespace utils {

template<typename T, std::size_t Alignment = 64>
class aligned_allocator {
public:
    using value_type = T;
    using pointer = T*;
    using const_pointer = const T*;
    using reference = T&;
    using const_reference = const T&;
    using size_type = std::size_t;
    using difference_type = std::ptrdiff_t;

    template<typename U>
    struct rebind {
        using other = aligned_allocator<U, Alignment>;
    };

    aligned_allocator() noexcept = default;

    template<typename U>
    aligned_allocator(const aligned_allocator<U, Alignment>&) noexcept {}

    pointer allocate(size_type n) {
        if (n == 0) {
            return nullptr;
        }

        void* ptr = nullptr;
        size_type size = n * sizeof(T);

#ifdef _WIN32
        ptr = _aligned_malloc(size, Alignment);
        if (!ptr) {
            throw std::bad_alloc();
        }
#else
        if (posix_memalign(&ptr, Alignment, size) != 0) {
            throw std::bad_alloc();
        }
#endif

        return static_cast<pointer>(ptr);
    }

    void deallocate(pointer ptr, size_type) noexcept {
        if (ptr) {
#ifdef _WIN32
            _aligned_free(ptr);
#else
            free(ptr);
#endif
        }
    }

    template<typename U, typename... Args>
    void construct(U* ptr, Args&&... args) {
        ::new(static_cast<void*>(ptr)) U(std::forward<Args>(args)...);
    }

    template<typename U>
    void destroy(U* ptr) {
        ptr->~U();
    }

    bool operator==(const aligned_allocator& other) const noexcept {
        return true;
    }

    bool operator!=(const aligned_allocator& other) const noexcept {
        return false;
    }
};

// Utility functions for aligned allocation
inline void* aligned_alloc(size_t size, size_t alignment) {
    void* ptr = nullptr;
#ifdef _WIN32
    ptr = _aligned_malloc(size, alignment);
#else
    if (posix_memalign(&ptr, alignment, size) != 0) {
        ptr = nullptr;
    }
#endif
    return ptr;
}

inline void aligned_free(void* ptr) {
#ifdef _WIN32
    _aligned_free(ptr);
#else
    free(ptr);
#endif
}

} // namespace utils
} // namespace meteor 