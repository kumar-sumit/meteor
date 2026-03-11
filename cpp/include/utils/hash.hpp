#pragma once

#include <cstdint>
#include <cstddef>
#include <immintrin.h>

namespace meteor {
namespace utils {

// SIMD-optimized hash functions
class FastHash {
public:
    // xxHash-inspired algorithm with SIMD optimization
    static uint64_t xxhash64(const void* data, size_t len, uint64_t seed = 0);
    
    // CityHash-inspired algorithm
    static uint64_t cityhash64(const void* data, size_t len);
    
    // Murmur3 hash with SIMD
    static uint64_t murmur3_64(const void* data, size_t len, uint64_t seed = 0);
    
    // FNV-1a hash (simple fallback)
    static uint64_t fnv1a_64(const void* data, size_t len);
    
    // Consistent hash for sharding
    static uint32_t consistent_hash(const void* data, size_t len, uint32_t shard_count);
    
private:
    // SIMD helper functions
    static inline uint64_t rotl64(uint64_t x, int r) {
        return (x << r) | (x >> (64 - r));
    }
    
    static inline uint64_t fmix64(uint64_t k) {
        k ^= k >> 33;
        k *= 0xff51afd7ed558ccdULL;
        k ^= k >> 33;
        k *= 0xc4ceb9fe1a85ec53ULL;
        k ^= k >> 33;
        return k;
    }
};

// Compile-time string hash for switch statements
constexpr uint64_t string_hash(const char* str, size_t len) {
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (size_t i = 0; i < len; ++i) {
        hash ^= static_cast<uint64_t>(str[i]);
        hash *= 0x100000001b3ULL;
    }
    return hash;
}

// Macro for compile-time string hashing
#define HASH(str) (::meteor::utils::string_hash(str, sizeof(str) - 1))

} // namespace utils
} // namespace meteor 