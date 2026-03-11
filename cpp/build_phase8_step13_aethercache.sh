#!/bin/bash

# **PHASE 8 STEP 13: AETHERCACHE OPTIMIZED CUCKOO HASH TABLE BUILD SCRIPT**
# Implementing state-of-the-art cuckoo hash table based on NSDI '13 and EuroSys '14 research:
# - Bucketized cuckoo hash table with partial hash tags for cache efficiency
# - Optimistic lock-free reads with version counters (zero write overhead)
# - BFS pathfinding for minimal displacement paths (5-6 max vs hundreds)
# - Fine-grained locking with globally consistent ordering (deadlock-free)
# Target: 2M+ RPS + sub-500μs P99 + zero read contention + unlimited keys

set -e

echo "🚀 Building Phase 8 Step 13: AetherCache Optimized Cuckoo Hash Table..."

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
echo "🔧 Compiling AetherCache with optimistic reads and BFS pathfinding..."
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
    sharded_server_phase8_step13_aethercache.cpp \
    -o meteor_phase8_step13_aethercache \
    -luring

if [ $? -eq 0 ]; then
    echo "✅ Phase 8 Step 13 build successful!"
    echo "📊 Binary: meteor_phase8_step13_aethercache"
    echo "🎯 Features: AetherCache + Optimistic reads + BFS pathfinding + Fine-grained locks"
    echo "🚀 Expected: 2M+ RPS + Sub-500μs P99 + Zero read contention"
else
    echo "❌ Build failed!"
    exit 1
fi

