#!/bin/bash

# **PHASE 8 STEP 5: ULTRA-SIMPLE WORKING IMPLEMENTATION BUILD SCRIPT**
# Back to basics approach - proven Phase 6 Step 3 foundation with:
# - NO connection migration (DragonflyDB never migrates)
# - Simple std::unordered_map (focus on architecture, not data structures)
# - Proven pipeline batch processing
# - All commands processed locally
# Target: Working implementation with no SET errors, sub-ms latency

set -e

echo "🚀 Building Phase 8 Step 5: Ultra-Simple Working Implementation..."

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
echo "⚙️  Compiling sharded_server_phase8_step5_simple_working.cpp..."
$COMPILER $ALL_FLAGS -o meteor_phase8_step5_simple_working sharded_server_phase8_step5_simple_working.cpp

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📊 Executable: meteor_phase8_step5_simple_working"
    echo ""
    echo "🎯 Phase 8 Step 5 Features:"
    echo "   • Proven Phase 6 Step 3 foundation (179K RPS baseline)"
    echo "   • NO connection migration (like real DragonflyDB)"
    echo "   • Simple std::unordered_map data structure"
    echo "   • All pipeline commands processed locally"
    echo "   • Focus on architecture over exotic data structures"
    echo "   • Target: No SET errors, sub-ms latency"
    echo ""
    echo "🚀 Ready to test ultra-simple working implementation!"
else
    echo "❌ Build failed!"
    exit 1
fi