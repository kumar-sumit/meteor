#include "../../include/utils/simd_utils.hpp"
#include <cstring>

namespace meteor {
namespace utils {

#ifdef ENABLE_SIMD
#include <immintrin.h>

bool simd_compare_strings(const char* str1, const char* str2, size_t len) {
    if (len == 0) return true;
    
    // Use SIMD for larger strings
    if (len >= 32) {
        size_t simd_len = len & ~31; // Round down to multiple of 32
        
        for (size_t i = 0; i < simd_len; i += 32) {
            __m256i v1 = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(str1 + i));
            __m256i v2 = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(str2 + i));
            __m256i cmp = _mm256_cmpeq_epi8(v1, v2);
            
            if (_mm256_movemask_epi8(cmp) != 0xFFFFFFFF) {
                return false;
            }
        }
        
        // Handle remaining bytes
        return memcmp(str1 + simd_len, str2 + simd_len, len - simd_len) == 0;
    }
    
    return memcmp(str1, str2, len) == 0;
}

uint64_t simd_hash_xxhash(const char* data, size_t len) {
    // Simple xxHash-like implementation with SIMD
    const uint64_t PRIME64_1 = 0x9E3779B185EBCA87ULL;
    const uint64_t PRIME64_2 = 0xC2B2AE3D27D4EB4FULL;
    const uint64_t PRIME64_3 = 0x165667B19E3779F9ULL;
    const uint64_t PRIME64_4 = 0x85EBCA77C2B2AE63ULL;
    const uint64_t PRIME64_5 = 0x27D4EB2F165667C5ULL;
    
    uint64_t h64;
    
    if (len >= 32) {
        uint64_t v1 = PRIME64_1 + PRIME64_2;
        uint64_t v2 = PRIME64_2;
        uint64_t v3 = 0;
        uint64_t v4 = static_cast<uint64_t>(-static_cast<int64_t>(PRIME64_1));
        
        const char* end = data + len;
        const char* limit = end - 32;
        
        do {
            v1 = ((v1 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) << 31) | 
                 ((v1 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) >> 33);
            v1 *= PRIME64_1;
            data += 8;
            
            v2 = ((v2 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) << 31) | 
                 ((v2 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) >> 33);
            v2 *= PRIME64_1;
            data += 8;
            
            v3 = ((v3 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) << 31) | 
                 ((v3 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) >> 33);
            v3 *= PRIME64_1;
            data += 8;
            
            v4 = ((v4 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) << 31) | 
                 ((v4 + (*reinterpret_cast<const uint64_t*>(data) * PRIME64_2)) >> 33);
            v4 *= PRIME64_1;
            data += 8;
        } while (data <= limit);
        
        h64 = ((v1 << 1) | (v1 >> 63)) + ((v2 << 7) | (v2 >> 57)) + 
              ((v3 << 12) | (v3 >> 52)) + ((v4 << 18) | (v4 >> 46));
        
        v1 *= PRIME64_2;
        v1 = ((v1 << 31) | (v1 >> 33)) * PRIME64_1;
        h64 ^= v1;
        h64 = h64 * PRIME64_1 + PRIME64_4;
        
        v2 *= PRIME64_2;
        v2 = ((v2 << 31) | (v2 >> 33)) * PRIME64_1;
        h64 ^= v2;
        h64 = h64 * PRIME64_1 + PRIME64_4;
        
        v3 *= PRIME64_2;
        v3 = ((v3 << 31) | (v3 >> 33)) * PRIME64_1;
        h64 ^= v3;
        h64 = h64 * PRIME64_1 + PRIME64_4;
        
        v4 *= PRIME64_2;
        v4 = ((v4 << 31) | (v4 >> 33)) * PRIME64_1;
        h64 ^= v4;
        h64 = h64 * PRIME64_1 + PRIME64_4;
    } else {
        h64 = PRIME64_5;
    }
    
    h64 += static_cast<uint64_t>(len);
    
    while (data + 8 <= data + len) {
        uint64_t k1 = *reinterpret_cast<const uint64_t*>(data);
        k1 *= PRIME64_2;
        k1 = ((k1 << 31) | (k1 >> 33)) * PRIME64_1;
        h64 ^= k1;
        h64 = ((h64 << 27) | (h64 >> 37)) * PRIME64_1 + PRIME64_4;
        data += 8;
    }
    
    if (data + 4 <= data + len) {
        h64 ^= static_cast<uint64_t>(*reinterpret_cast<const uint32_t*>(data)) * PRIME64_1;
        h64 = ((h64 << 23) | (h64 >> 41)) * PRIME64_2 + PRIME64_3;
        data += 4;
    }
    
    while (data < data + len) {
        h64 ^= static_cast<uint64_t>(*data) * PRIME64_5;
        h64 = ((h64 << 11) | (h64 >> 53)) * PRIME64_1;
        data++;
    }
    
    h64 ^= h64 >> 33;
    h64 *= PRIME64_2;
    h64 ^= h64 >> 29;
    h64 *= PRIME64_3;
    h64 ^= h64 >> 32;
    
    return h64;
}

#else

bool simd_compare_strings(const char* str1, const char* str2, size_t len) {
    return memcmp(str1, str2, len) == 0;
}

uint64_t simd_hash_xxhash(const char* data, size_t len) {
    // Fallback hash function
    uint64_t hash = 0x9E3779B185EBCA87ULL;
    for (size_t i = 0; i < len; ++i) {
        hash ^= static_cast<uint64_t>(data[i]);
        hash *= 0x100000001B3ULL;
    }
    return hash;
}

#endif

} // namespace utils
} // namespace meteor 