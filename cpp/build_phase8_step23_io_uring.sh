#!/bin/bash

# **PHASE 8 STEP 23: IO_URING + SQPOLL + ZERO-COPY BUILD SCRIPT**
# Building the breakthrough io_uring implementation with async I/O and zero-copy

echo "🚀 Building Phase 8 Step 23: io_uring + SQPOLL + Zero-Copy..."
echo "📋 Features:"
echo "   ✅ io_uring async I/O (no epoll)"
echo "   ✅ SQPOLL kernel polling thread"
echo "   ✅ Zero-copy pre-registered buffers"
echo "   ✅ True shared-nothing architecture"
echo "   ✅ Direct DMA for network I/O"

# Compiler settings for maximum performance
CXX="g++"
CXXFLAGS="-std=c++17 -O3 -march=native -mtune=native"
CXXFLAGS="$CXXFLAGS -flto -fuse-linker-plugin"
CXXFLAGS="$CXXFLAGS -DNDEBUG -funroll-loops -finline-functions"

# **IO_URING SPECIFIC FLAGS**
CXXFLAGS="$CXXFLAGS -DHAS_IO_URING"

# Threading and performance flags
CXXFLAGS="$CXXFLAGS -pthread -fno-stack-protector"
CXXFLAGS="$CXXFLAGS -falign-functions=32 -falign-loops=32"

# **IO_URING LIBRARIES**
LIBS="-luring -lpthread"

# Source and target
SOURCE="sharded_server_phase8_step23_io_uring.cpp"
TARGET="meteor_phase8_step23_io_uring"

# Build command
BUILD_CMD="$CXX $CXXFLAGS -o $TARGET $SOURCE $LIBS"

echo "🔧 Build command: $BUILD_CMD"
echo ""

# Execute build
if $BUILD_CMD; then
    echo ""
    echo "✅ BUILD SUCCESSFUL!"
    echo ""
    echo "🎯 **IO_URING + SQPOLL + ZERO-COPY SERVER READY**"
    echo ""
    echo "📊 **EXPECTED BREAKTHROUGH PERFORMANCE:**"
    echo "   🚀 Target: 8M+ RPS (2x improvement over epoll)"
    echo "   ⚡ P99 Latency: <0.5ms (zero I/O overhead)"
    echo "   🔥 Zero syscalls (SQPOLL kernel thread)"
    echo "   💾 Zero memcpy (DMA direct to buffers)"
    echo ""
    echo "🏃‍♂️ **READY TO TEST:**"
    echo "   ./meteor_phase8_step23_io_uring -h 127.0.0.1 -p 6380 -c 12"
    echo ""
    echo "🎯 **ARCHITECTURE HIGHLIGHTS:**"
    echo "   • io_uring replaces epoll for 100% async I/O"
    echo "   • SQPOLL eliminates accept/recv/send syscalls"
    echo "   • Pre-registered buffers enable zero-copy DMA"
    echo "   • True shared-nothing: per-core isolation"
    echo "   • 1024 zero-copy buffers per core (64KB each)"
    echo ""
    echo "🏆 **MISSION: Beat DragonflyDB with io_uring breakthrough!**"
else
    echo ""
    echo "❌ BUILD FAILED!"
    echo ""
    echo "🔍 **TROUBLESHOOTING:**"
    echo "   1. Install liburing: sudo apt-get install liburing-dev"
    echo "   2. Check kernel version: uname -r (need 5.1+)"
    echo "   3. Verify io_uring support: ls /usr/include/liburing.h"
    echo ""
    echo "📋 **REQUIREMENTS:**"
    echo "   • Linux kernel 5.1+ (for io_uring)"
    echo "   • liburing-dev package"
    echo "   • GCC 7+ with C++17 support"
    echo ""
    exit 1
fi
