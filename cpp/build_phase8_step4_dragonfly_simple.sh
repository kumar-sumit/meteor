#!/bin/bash

# **PHASE 8 STEP 4: TRUE DRAGONFLY-STYLE SIMPLIFICATION BUILD SCRIPT**
# Clean implementation based on actual DragonflyDB approach
# Features:
# - Simple Robin Hood hashing with MSB buckets (like DragonflyDB)
# - Fixed bucket arrays (54 regular + 6 stash, 14 slots each)
# - Minimal atomic operations (simple compare-and-swap)
# - Zero dynamic allocation in hot path
# - Cache-efficient linear probing
# - Displacement-based insertion
# Target: 140K+ RPS, P99 < 10ms

set -e

echo "🚀 Building Phase 8 Step 4: True DragonflyDB-Style Simplification..."

# Detect architecture and set appropriate flags
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    echo "📱 Detected ARM64 (Apple Silicon)"
    ARCH_FLAGS="-mcpu=apple-m1 -mtune=apple-m1"
    SIMD_FLAGS="-msse4.2 -DUSE_NEON"
    INCLUDE_PATHS="-I/opt/homebrew/include -I/usr/local/include -I/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1 -I/Library/Developer/CommandLineTools/usr/include/c++/v1"
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "🖥️  Detected x86_64"
    ARCH_FLAGS="-march=native -mtune=native"
    SIMD_FLAGS="-mavx2 -msse4.2 -mbmi2 -DUSE_AVX2"
    INCLUDE_PATHS=""
else
    echo "❓ Unknown architecture: $ARCH, using generic flags"
    ARCH_FLAGS=""
    SIMD_FLAGS="-msse4.2"
    INCLUDE_PATHS=""
fi

# Compiler selection and flags
if command -v clang++ &> /dev/null; then
    COMPILER="clang++"
    echo "🔧 Using Clang++ compiler"
elif command -v g++ &> /dev/null; then
    COMPILER="g++"
    echo "🔧 Using G++ compiler"
else
    echo "❌ No suitable C++ compiler found"
    exit 1
fi

# Optimization flags for maximum performance
OPTIMIZATION_FLAGS="-O3 -DNDEBUG -flto"

# Performance and debugging flags
PERFORMANCE_FLAGS="-ffast-math -funroll-loops -finline-functions -fomit-frame-pointer"
DEBUG_FLAGS="-g -DDEBUG_PIPELINE -DDEBUG_PERFORMANCE"

# Threading and system flags
THREADING_FLAGS="-pthread -std=c++17"
SYSTEM_FLAGS="-DHAS_LINUX_EPOLL -DUSE_EPOLL"

# Warning flags
WARNING_FLAGS="-Wall -Wextra -Wno-unused-parameter -Wno-unused-variable"

# Memory and sanitizer flags (disabled for performance)
# SANITIZER_FLAGS="-fsanitize=address -fsanitize=thread"
SANITIZER_FLAGS=""

# Combine all flags
ALL_FLAGS="$THREADING_FLAGS $OPTIMIZATION_FLAGS $PERFORMANCE_FLAGS $DEBUG_FLAGS $SYSTEM_FLAGS $WARNING_FLAGS $ARCH_FLAGS $SIMD_FLAGS $SANITIZER_FLAGS $INCLUDE_PATHS"

echo "🔨 Compilation flags: $ALL_FLAGS"

# Compile
echo "⚙️  Compiling sharded_server_phase8_step4_dragonfly_simple.cpp..."
$COMPILER $ALL_FLAGS \
    -o meteor_phase8_step4_dragonfly_simple \
    sharded_server_phase8_step4_dragonfly_simple.cpp

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📊 Executable: meteor_phase8_step4_dragonfly_simple"
    echo ""
    echo "🎯 Phase 8 Step 4 Features:"
    echo "   • True DragonflyDB-style Robin Hood hashing"
    echo "   • MSB bucket selection for cache efficiency"
    echo "   • Fixed bucket arrays (54 regular + 6 stash)"
    echo "   • 14 slots per bucket (like DragonflyDB)"
    echo "   • Minimal atomic operations"
    echo "   • Zero dynamic allocation in hot path"
    echo "   • Simple displacement-based insertion"
    echo "   • Target: 140K+ RPS, P99 < 10ms"
    echo ""
    echo "🚀 Ready to test simplified DragonflyDB implementation!"
else
    echo "❌ Build failed!"
    exit 1
fi