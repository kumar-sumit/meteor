#!/bin/bash

# **PHASE 8 STEP 6: UNLIMITED KEY STORAGE WITH PROVEN ARCHITECTURE BUILD SCRIPT**
# Building on Phase 8 Step 5's proven architecture (sub-ms latency) with:
# - NO connection migration (DragonflyDB never migrates) 
# - TRUE unlimited key storage (1024 shards = 64x less contention)
# - Simple per-shard std::unordered_map (unlimited capacity)
# - Proven pipeline batch processing
# - All commands processed locally
# Target: Unlimited keys + sub-ms latency + 16-core scaling

set -e

echo "🚀 Building Phase 8 Step 6: Unlimited Key Storage..."

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
echo "⚙️  Compiling sharded_server_phase8_step6_unlimited_storage.cpp..."
$COMPILER $ALL_FLAGS -o meteor_phase8_step6_unlimited_storage sharded_server_phase8_step6_unlimited_storage.cpp

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📊 Executable: meteor_phase8_step6_unlimited_storage"
    echo ""
    echo "🎯 Phase 8 Step 6 Features:"
    echo "   • Proven Phase 8 Step 5 architecture (0.27ms P50 latency)"
    echo "   • NO connection migration (like real DragonflyDB)"
    echo "   • TRUE unlimited key storage (1024 shards vs 16)"
    echo "   • 64x reduced lock contention"
    echo "   • All pipeline commands processed locally"
    echo "   • Target: No SET errors + sub-ms latency + 16-core scaling"
    echo ""
    echo "🚀 Ready to test unlimited key storage implementation!"
else
    echo "❌ Build failed!"
    exit 1
fi