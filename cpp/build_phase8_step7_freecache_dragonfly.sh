#!/bin/bash

# **PHASE 8 STEP 7: FREECACHE + DRAGONFLY HYBRID STORAGE BUILD SCRIPT**
# Revolutionary hybrid approach combining:
# - FreeCache: 256 segments, ring buffer storage, zero GC overhead
# - DragonflyDB: B+ tree nodes for O(log N) binary search
# - Per-core design: Each core has private storage, no contention
# - Unlimited scalability: No capacity limits, no SET failures
# Target: TRUE unlimited keys + zero SET failures + sub-ms latency + 16-core scaling

set -e

echo "🚀 Building Phase 8 Step 7: FreeCache + DragonflyDB Hybrid Storage..."

# Detect architecture and set appropriate flags
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    echo "📱 Detected ARM64 (Apple Silicon)"
    ARCH_FLAGS="-mcpu=apple-m1 -mtune=apple-m1"
    SIMD_FLAGS="-msse4.2 -DUSE_NEON"
    INCLUDE_PATHS="-I/opt/homebrew/include -I/usr/local/include"
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "🖥️  Detected x86_64"
    ARCH_FLAGS="-march=native -mtune=native"
    SIMD_FLAGS="-mavx2 -msse4.2 -mbmi2 -DUSE_AVX2"
    INCLUDE_PATHS=""
else
    echo "❓ Unknown architecture: $ARCH"
    ARCH_FLAGS=""
    SIMD_FLAGS=""
    INCLUDE_PATHS=""
fi

# Compiler selection
if command -v g++ &> /dev/null; then
    COMPILER="g++"
    echo "🔧 Using G++ compiler"
elif command -v clang++ &> /dev/null; then
    COMPILER="clang++"
    echo "🔧 Using Clang++ compiler"
else
    echo "❌ No suitable C++ compiler found"
    exit 1
fi

# Threading and system flags
THREADING_FLAGS="-pthread -std=c++17"
SYSTEM_FLAGS="-DHAS_LINUX_EPOLL -DUSE_EPOLL"

# Optimization flags
OPTIMIZATION_FLAGS="-O3 -DNDEBUG -flto -ffast-math -funroll-loops -finline-functions -fomit-frame-pointer"

# Debug flags (keep some for troubleshooting)
DEBUG_FLAGS="-g -DDEBUG_PIPELINE -DDEBUG_PERFORMANCE"

# Warning flags
WARNING_FLAGS="-Wall -Wextra -Wno-unused-parameter -Wno-unused-variable"

# Combine all flags
ALL_FLAGS="$THREADING_FLAGS $OPTIMIZATION_FLAGS $DEBUG_FLAGS $SYSTEM_FLAGS $WARNING_FLAGS $ARCH_FLAGS $SIMD_FLAGS $INCLUDE_PATHS"

echo "🔨 Compilation flags: $ALL_FLAGS"

# Compile
echo "⚙️  Compiling sharded_server_phase8_step7_true_per_core.cpp..."
$COMPILER $ALL_FLAGS -o meteor_phase8_step7_freecache_dragonfly sharded_server_phase8_step7_true_per_core.cpp

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📊 Executable: meteor_phase8_step7_freecache_dragonfly"
    echo ""
    echo "🎯 Phase 8 Step 7 Features:"
    echo "   • FreeCache: 256 segments, zero GC overhead"
    echo "   • DragonflyDB: B+ tree nodes with binary search"
    echo "   • Per-core private storage (no contention)"
    echo "   • Unlimited key capacity (no SET failures)"
    echo "   • O(log N) lookups vs O(1) hash with collisions"
    echo "   • NO connection migration (like real DragonflyDB)"
    echo "   • Target: 16-core scaling + sub-ms latency"
    echo ""
    echo "🚀 Ready to test the revolutionary hybrid storage!"
else
    echo "❌ Build failed!"
    exit 1
fi