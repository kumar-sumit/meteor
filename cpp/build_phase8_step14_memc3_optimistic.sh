#!/bin/bash

# **PHASE 8 STEP 14: MEMC3 OPTIMISTIC CUCKOO BUILD SCRIPT**
# Implementing true MemC3-style optimistic cuckoo hashing based on NSDI '13 paper:
# - Bucketized design with 4 slots per bucket
# - Version counters for optimistic locking  
# - Concurrent readers, serialized writers
# - High load factor (>95% occupancy)
# - Cache-friendly layout with alignment
# Target: 2M+ RPS + sub-500μs P99 + unlimited storage + zero SET failures

set -e

echo "🚀 Building Phase 8 Step 14: MemC3 Optimistic Cuckoo Hash Table..."

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
    sharded_server_phase8_step14_memc3_simple.cpp \
    -o meteor_phase8_step14_memc3_simple

if [ $? -eq 0 ]; then
    echo "✅ Phase 8 Step 14 build successful!"
    echo "📊 Binary: meteor_phase8_step14_memc3_simple"
    echo "🎯 Features: MemC3 + Optimistic reads + Concurrent cuckoo + >95% occupancy"
    echo "🚀 Expected: 2M+ RPS + Sub-500μs P99 + Zero SET failures"
else
    echo "❌ Build failed!"
    exit 1
fi
