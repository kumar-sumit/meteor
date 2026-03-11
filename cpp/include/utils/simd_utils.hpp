#pragma once

#include <cstddef>
#include <cstdint>

namespace meteor {
namespace utils {

// SIMD-optimized string comparison
bool simd_compare_strings(const char* str1, const char* str2, size_t len);

// SIMD-optimized hash function (xxHash-like)
uint64_t simd_hash_xxhash(const char* data, size_t len);

} // namespace utils
} // namespace meteor 