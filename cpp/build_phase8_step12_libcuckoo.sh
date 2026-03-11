#!/bin/bash

# **PHASE 8 STEP 12: LIBCUCKOO HIGH-PERFORMANCE HASH TABLE BUILD SCRIPT**
# Replacing FreeCache with libcuckoo from https://github.com/efficient/libcuckoo:
# - ONE libcuckoo hash table per core (optimal concurrent performance)
# - High-performance concurrent hash table with multiple readers/writers
# - Header-only library with optimized atomic operations
# - Better performance than traditional hash tables with locking
# Target: 1.9M+ RPS + zero contention + unlimited keys + sub-ms latency

set -e

echo "🚀 Building Phase 8 Step 12: LibCuckoo High-Performance Hash Table..."

# Detect architecture and set appropriate flags
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    echo "📱 Detected ARM64 (Apple Silicon)"
    ARCH_FLAGS="-mcpu=apple-m1 -mtune=apple-m1"
    SIMD_FLAGS="-msse4.2 -DUSE_NEON"
    INCLUDE_PATHS="-I/opt/homebrew/include -I/usr/local/include -I."
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "💻 Detected x86_64 (Intel/AMD)"
    ARCH_FLAGS="-march=native -mtune=native"
    SIMD_FLAGS="-mavx2 -msse4.2 -DUSE_AVX2"
    INCLUDE_PATHS="-I."
else
    echo "⚠️ Unknown architecture: $ARCH, using generic flags"
    ARCH_FLAGS=""
    SIMD_FLAGS=""
    INCLUDE_PATHS="-I."
fi

# Build with maximum optimizations
echo "🔧 Compiling LibCuckoo hash table with concurrent readers/writers..."
g++ -std=c++17 \
    $ARCH_FLAGS \
    $SIMD_FLAGS \
    $INCLUDE_PATHS \
    -O3 -DNDEBUG \
    -flto \
    -funroll-loops \
    -finline-functions \
    -ffast-math \
    -pthread \
    -DLINUX_BUILD \
    -DUSE_EPOLL \
    -DUSE_IO_URING \
    sharded_server_phase8_step12_libcuckoo.cpp \
    -o meteor_phase8_step12_libcuckoo \
    -luring

if [ $? -eq 0 ]; then
    echo "✅ Phase 8 Step 12 build successful!"
    echo "📊 Binary: meteor_phase8_step12_libcuckoo"
    echo "🎯 Features: LibCuckoo + Concurrent hash table + Zero contention"
    echo "🚀 Expected: 1.9M+ RPS + Zero contention + Unlimited keys"
else
    echo "❌ Build failed!"
    exit 1
fi

