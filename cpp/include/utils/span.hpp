#pragma once

#include <cstddef>
#include <iterator>
#include <type_traits>

namespace meteor {
namespace utils {

// Simple span implementation for zero-copy operations
template<typename T>
class span {
public:
    using element_type = T;
    using value_type = std::remove_cv_t<T>;
    using size_type = std::size_t;
    using difference_type = std::ptrdiff_t;
    using pointer = T*;
    using const_pointer = const T*;
    using reference = T&;
    using const_reference = const T&;
    using iterator = T*;
    using const_iterator = const T*;
    
    constexpr span() noexcept : data_(nullptr), size_(0) {}
    
    constexpr span(pointer data, size_type size) noexcept 
        : data_(data), size_(size) {}
    
    template<typename Container>
    constexpr span(Container& container) noexcept
        : data_(container.data()), size_(container.size()) {}
    
    template<typename Container>
    constexpr span(const Container& container) noexcept
        : data_(container.data()), size_(container.size()) {}
    
    constexpr span(const span& other) noexcept = default;
    constexpr span& operator=(const span& other) noexcept = default;
    
    constexpr iterator begin() const noexcept { return data_; }
    constexpr iterator end() const noexcept { return data_ + size_; }
    constexpr const_iterator cbegin() const noexcept { return data_; }
    constexpr const_iterator cend() const noexcept { return data_ + size_; }
    
    constexpr reference operator[](size_type index) const { return data_[index]; }
    constexpr reference at(size_type index) const { return data_[index]; }
    constexpr reference front() const { return data_[0]; }
    constexpr reference back() const { return data_[size_ - 1]; }
    constexpr pointer data() const noexcept { return data_; }
    
    constexpr size_type size() const noexcept { return size_; }
    constexpr size_type size_bytes() const noexcept { return size_ * sizeof(element_type); }
    constexpr bool empty() const noexcept { return size_ == 0; }
    
    constexpr span<element_type> first(size_type count) const {
        return span<element_type>(data_, count);
    }
    
    constexpr span<element_type> last(size_type count) const {
        return span<element_type>(data_ + size_ - count, count);
    }
    
    constexpr span<element_type> subspan(size_type offset, size_type count = SIZE_MAX) const {
        if (count == SIZE_MAX) {
            count = size_ - offset;
        }
        return span<element_type>(data_ + offset, count);
    }
    
private:
    pointer data_;
    size_type size_;
    
    static constexpr size_type SIZE_MAX = static_cast<size_type>(-1);
};

// Deduction guides
template<typename T>
span(T*, std::size_t) -> span<T>;

template<typename Container>
span(Container&) -> span<typename Container::value_type>;

template<typename Container>
span(const Container&) -> span<const typename Container::value_type>;

} // namespace utils
} // namespace meteor 