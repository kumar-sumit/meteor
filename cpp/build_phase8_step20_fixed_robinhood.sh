#!/bin/bash

# **PHASE 8 STEP 20: FIXED ROBIN HOOD + EPOLL BUILD SCRIPT**
# Applying correct Robin Hood logic from production reference + epoll fix:
# - FIXED: Using -DHAS_LINUX_EPOLL for optimal I/O performance (580K+ RPS!)
# - FIXED: Robin Hood insertion logic with proper key existence check
# - FIXED: Placement new for proper object construction in hash table
# - PRESERVED: All working connection handling and batch processing
# Target: 580K+ RPS + sub-500μs P99 + ZERO SET failures + unlimited storage

set -e

echo "🚀 Building Phase 8 Step 20: Fixed Robin Hood + epoll..."

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
    sharded_server_phase8_step20_fixed_robinhood.cpp \
    -o meteor_phase8_step20_fixed_robinhood

if [ $? -eq 0 ]; then
    echo "✅ Phase 8 Step 20 build successful!"
    echo "📊 Binary: meteor_phase8_step20_fixed_robinhood"
    echo "🎯 Features: FIXED Robin Hood + epoll performance + proper key handling"
    echo "🚀 Expected: 580K+ RPS + Sub-500μs P99 + ZERO SET failures"
else
    echo "❌ Build failed!"
    exit 1
fi
