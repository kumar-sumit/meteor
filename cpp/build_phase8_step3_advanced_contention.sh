#!/bin/bash

# **PHASE 8 STEP 3: Build Script for Advanced Contention Mitigation**
# Building the advanced contention mitigation implementation for sub-1ms P99 latency

echo "🚀 Building Phase 8 Step 3: Advanced Contention Mitigation..."

# Detect architecture for optimal compilation
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Architecture-specific compiler settings
if [[ "$ARCH" == "arm64" ]]; then
    echo "Configuring for ARM64 (Apple Silicon)..."
    COMPILER="clang++"
    ARCH_FLAGS="-DHAS_MACOS_KQUEUE"
    SIMD_FLAGS="-march=armv8-a+simd"
    # Add macOS system include paths
    INCLUDE_FLAGS="-I/usr/local/include -I/opt/homebrew/include"
else
    echo "Configuring for x86_64..."
    COMPILER="g++"
    ARCH_FLAGS="-DHAS_LINUX_EPOLL"
    SIMD_FLAGS="-march=native -mavx2 -mavx512f -mavx512dq -mavx512cd -mavx512bw -mavx512vl"
    INCLUDE_FLAGS=""
fi

# Common compilation flags
COMMON_FLAGS="-std=c++17 -O3 -pthread"
OPTIMIZATION_FLAGS="-finline-functions -funroll-loops -ffast-math"
DEBUG_FLAGS="-g -DDEBUG_BUILD"

# Final compilation command
COMPILE_CMD="$COMPILER $COMMON_FLAGS $ARCH_FLAGS $SIMD_FLAGS $OPTIMIZATION_FLAGS $DEBUG_FLAGS $INCLUDE_FLAGS"

echo "Compilation command: $COMPILE_CMD"
echo "Building sharded_server_phase8_step3_advanced_contention.cpp..."

$COMPILE_CMD sharded_server_phase8_step3_advanced_contention.cpp -o meteor_phase8_step3_advanced_contention

if [ $? -eq 0 ]; then
    echo "✅ Build successful! Executable: meteor_phase8_step3_advanced_contention"
    echo ""
    echo "🎯 Phase 8 Step 3 Features:"
    echo "  - Enhanced Cuckoo Hashing with improved key distribution"
    echo "  - Advanced SCA with adaptive thresholds and intelligent backoff"
    echo "  - Hotspot Detection and dynamic load balancing"
    echo "  - Smart bucket selection to avoid contentious areas"
    echo "  - Adaptive backoff up to 1ms for extreme contention"
    echo "  - Load-balanced stash bucket selection"
    echo "  - Zero memory overhead per entry beyond Dashtable structure"
    echo ""
    echo "🚀 Ready to test for sub-1ms P99 latency!"
    echo "Target: 140K+ RPS with P99 < 1ms (eliminate 120ms spikes)"
else
    echo "❌ Build failed!"
    exit 1
fi