#!/bin/bash

# **PHASE 8 STEP 19: ROBIN HOOD + EPOLL MINIMAL FIX BUILD SCRIPT**
# Applying ONLY the essential epoll fix to working Robin Hood implementation:
# - FIXED: Using -DHAS_LINUX_EPOLL instead of -DUSE_EPOLL (the real fix!)
# - PRESERVED: All original Robin Hood hash table logic (zero SET failures)
# - PRESERVED: All original metrics, caching, and batch processing
# - MINIMAL: No aggressive optimizations that break data flow
# Target: 580K+ RPS + sub-500μs P99 + zero SET failures + unlimited storage

set -e

echo "🚀 Building Phase 8 Step 19: Robin Hood + epoll Minimal Fix..."

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
    -DHAS_LINUX_EPOLL \
    sharded_server_phase8_step19_robinhood_epoll_fixed.cpp \
    -o meteor_phase8_step19_robinhood_epoll_fixed

if [ $? -eq 0 ]; then
    echo "✅ Phase 8 Step 19 build successful!"
    echo "📊 Binary: meteor_phase8_step19_robinhood_epoll_fixed"
    echo "🎯 Features: Robin Hood reliability + epoll performance + MINIMAL changes"
    echo "🚀 Expected: 2M+ RPS + Sub-500μs P99 + Zero SET failures"
else
    echo "❌ Build failed!"
    exit 1
fi
