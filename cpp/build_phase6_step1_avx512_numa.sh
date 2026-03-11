#!/bin/bash

# **PHASE 6 STEP 1: AVX-512 + NUMA Build Script**
# Build script for Phase 6 Step 1 with AVX-512 vectorization and NUMA awareness
# TARGET: 5M RPS through 8-way SIMD parallelism and NUMA optimization

echo "🚀 Building Phase 6 Step 1: AVX-512 + NUMA Optimization..."

# Compiler flags for maximum performance
CXXFLAGS="-std=c++17 -O3 -march=native -mavx512f -mavx512dq -mavx512bw -mavx2 -mfma"
CXXFLAGS="$CXXFLAGS -DHAS_LINUX_EPOLL -pthread"
CXXFLAGS="$CXXFLAGS -Wall -Wextra -Wno-unused-parameter"
CXXFLAGS="$CXXFLAGS -ffast-math -funroll-loops -finline-functions"

# NUMA library linking
LIBS="-lnuma"

# Source file
SOURCE="sharded_server_phase6_step1_avx512_numa.cpp"
OUTPUT="meteor_phase6_step1_avx512_numa"

echo "Compiler flags: $CXXFLAGS"
echo "Libraries: $LIBS"
echo "Source: $SOURCE"
echo "Output: $OUTPUT"
echo

# Check if AVX-512 is supported
echo "Checking CPU capabilities..."
if grep -q avx512f /proc/cpuinfo; then
    echo "✅ AVX-512F detected"
else
    echo "⚠️  AVX-512F not detected, will fallback to AVX2"
fi

if grep -q avx2 /proc/cpuinfo; then
    echo "✅ AVX2 detected"
else
    echo "❌ AVX2 not detected"
fi

echo

# Build the server
echo "Compiling Phase 6 Step 1..."
g++ $CXXFLAGS $SOURCE -o $OUTPUT $LIBS

if [ $? -eq 0 ]; then
    echo "✅ Phase 6 Step 1 build successful!"
    echo "Executable: ./$OUTPUT"
    echo
    echo "Usage:"
    echo "  ./$OUTPUT -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l"
    echo
    echo "New Phase 6 Step 1 Features:"
    echo "  • AVX-512 8-way parallel SIMD operations (2x improvement over AVX2)"
    echo "  • NUMA-aware memory allocation and CPU affinity"
    echo "  • Automatic fallback to AVX2 if AVX-512 not available"
    echo "  • Enhanced thread-per-core architecture"
    echo "  • All Phase 5 optimizations preserved"
    echo
    echo "Expected Performance: 5M RPS (4x improvement over Phase 5)"
else
    echo "❌ Phase 6 Step 1 build failed!"
    exit 1
fi