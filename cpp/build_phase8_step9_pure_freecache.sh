#!/bin/bash

# **PHASE 8 STEP 9: PURE FREECACHE UNLIMITED STORAGE BUILD SCRIPT**
# FreeCache-inspired unlimited storage without B+ tree overhead:
# - NO connection migration (DragonflyDB never migrates)
# - 256 segments per core (FreeCache segmentation)
# - Simple std::unordered_map per segment (unlimited capacity)
# - Minimal per-segment locking (no global contention)
# - Proven pipeline batch processing
# Target: 1.9M+ RPS + zero SET failures + unlimited keys + sub-ms latency

set -e

echo "🚀 Building Phase 8 Step 9: Pure FreeCache Unlimited Storage..."

# Detect architecture and set appropriate flags
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    echo "📱 Detected ARM64 (Apple Silicon)"
    ARCH_FLAGS="-mcpu=apple-m1 -mtune=apple-m1"
    SIMD_FLAGS="-msse4.2 -DUSE_NEON"
    INCLUDE_PATHS="-I/opt/homebrew/include -I/usr/local/include"
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "💻 Detected x86_64 (Intel/AMD)"
    ARCH_FLAGS="-march=native -mtune=native"
    SIMD_FLAGS="-mavx2 -msse4.2 -DUSE_AVX2"
    INCLUDE_PATHS=""
else
    echo "⚠️ Unknown architecture: $ARCH, using generic flags"
    ARCH_FLAGS=""
    SIMD_FLAGS=""
    INCLUDE_PATHS=""
fi

# Build with maximum optimizations
echo "🔧 Compiling Pure FreeCache with 256 segments per core..."
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
    sharded_server_phase8_step9_pure_freecache.cpp \
    -o meteor_phase8_step9_pure_freecache \
    -luring

if [ $? -eq 0 ]; then
    echo "✅ Phase 8 Step 9 build successful!"
    echo "📊 Binary: meteor_phase8_step9_pure_freecache"
    echo "🎯 Features: Pure FreeCache + 256 segments + Unlimited capacity"
    echo "🚀 Expected: 1.9M+ RPS + Zero SET failures + Sub-ms latency"
else
    echo "❌ Build failed!"
    exit 1
fi

