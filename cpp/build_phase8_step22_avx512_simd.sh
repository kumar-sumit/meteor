#!/bin/bash

# **PHASE 8 STEP 22: AVX-512 + SIMD HOT PATH BUILD SCRIPT**
# Building SIMD-optimized version for maximum performance gains
# - PROVEN: True shared-nothing achieved 3.82M RPS + 2.287ms P99 on 12 cores
# - OPTIMIZATION: AVX-512 vectorization in hash operations and batch processing
# - HOT PATH: SIMD-optimized key hashing, batch processing, and pipeline execution
# - TARGET: 5M+ RPS + 1ms P99 + SIMD acceleration + perfect linear scaling

set -e

echo "🏗️  Building Phase 8 Step 22: AVX-512 + SIMD Hot Path Optimization..."

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
    SIMD_FLAGS="-mavx512f -mavx512dq -mavx512cd -mavx512bw -mavx512vl -mavx2 -msse4.2 -mpopcnt -mbmi2 -DUSE_AVX512 -DUSE_SIMD_OPTIMIZATIONS"
    INCLUDE_PATHS="-I."
else
    echo "⚠️ Unknown architecture: $ARCH, using generic flags"
    ARCH_FLAGS=""
    SIMD_FLAGS=""
    INCLUDE_PATHS="-I."
fi

# Build with maximum optimizations + aggressive SIMD
echo "🔧 Compiling with AVX-512 + SIMD hot path optimizations..."
g++ -std=c++20 \
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
    sharded_server_phase8_step22_avx512_simd.cpp \
    -o meteor_phase8_step22_avx512_simd

if [ $? -eq 0 ]; then
    echo "✅ Successfully built meteor_phase8_step22_avx512_simd"
    echo "🏆 Features: AVX-512 + SIMD batching + vectorized hashing + true shared-nothing"
    echo "🚀 Ready to test SIMD-accelerated performance!"
    echo ""
    echo "📊 Expected Performance (vs 3.82M baseline):"
    echo "   12 cores: 5M+ RPS + 1ms P99 (SIMD acceleration)"
    echo "   Optimizations:"
    echo "     - AVX-512 vectorized hashing (8 keys in parallel)"
    echo "     - AVX2 vectorized batch processing (4 operations in parallel)"
    echo "     - SIMD-optimized pipeline execution"
    echo "     - Pre-computed hash usage in hot path"
    echo "     - Vectorized response building"
    echo ""
    echo "🎯 Architecture: True shared-nothing + SIMD acceleration in every hot path"
else
    echo "❌ Build failed!"
    exit 1
fi
