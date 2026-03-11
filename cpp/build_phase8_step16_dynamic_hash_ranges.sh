#!/bin/bash

# **PHASE 8 STEP 16: DYNAMIC HASH RANGE PARTITIONING BUILD SCRIPT**
# Implementing unlimited storage with smart hash range partitioning:
# - std::unordered_map as proven, fast core data structure
# - Dynamic hash range partitioning within each shard
# - Automatic map creation when maps fill up (smart capacity management)
# - Efficient memory utilization by splitting hash ranges
# Target: 2M+ RPS + sub-500μs P99 + unlimited storage + zero SET failures

set -e

echo "🚀 Building Phase 8 Step 16: Dynamic Hash Range Partitioning..."

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
echo "🔧 Compiling MemC3 with optimistic reads and concurrent cuckoo hashing..."
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
    sharded_server_phase8_step16_dynamic_hash_ranges_clean.cpp \
    -o meteor_phase8_step16_dynamic_hash_ranges

if [ $? -eq 0 ]; then
    echo "✅ Phase 8 Step 16 build successful!"
    echo "📊 Binary: meteor_phase8_step16_dynamic_hash_ranges"
    echo "🎯 Features: Dynamic hash ranges + std::unordered_map + Smart partitioning + Unlimited storage"
    echo "🚀 Expected: 2M+ RPS + Sub-500μs P99 + Zero SET failures"
else
    echo "❌ Build failed!"
    exit 1
fi
