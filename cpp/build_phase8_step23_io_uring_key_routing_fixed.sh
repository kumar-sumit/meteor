#!/bin/bash

# **PHASE 8 STEP 23: IO_URING + KEY ROUTING FIXED**
# CRITICAL FIX: Consistent key-to-core routing for correct data access

echo "🚀 Building Phase 8 Step 23: io_uring + Key Routing Fixed..."
echo "📋 Features:"
echo "   ✅ FIXED: Consistent key-to-core routing (prevents cache misses)"
echo "   ✅ Proven epoll accepts (no connection resets)"
echo "   ✅ Optional io_uring for recv/send operations"
echo "   ✅ Connection migration for correct key placement"
echo "   ✅ True data consistency across cores"

# Compiler settings for maximum performance
CXX="g++"
CXXFLAGS="-std=c++17 -O3 -march=native -mtune=native"
CXXFLAGS="$CXXFLAGS -flto -fuse-linker-plugin"
CXXFLAGS="$CXXFLAGS -DNDEBUG -funroll-loops -finline-functions"

# **HYBRID EVENT SYSTEM FLAGS**
CXXFLAGS="$CXXFLAGS -DHAS_LINUX_EPOLL"

# Threading and performance flags
CXXFLAGS="$CXXFLAGS -pthread -fno-stack-protector"
CXXFLAGS="$CXXFLAGS -falign-functions=32 -falign-loops=32"

# **HYBRID LIBRARIES**: Both epoll and io_uring
LIBS="-luring -lpthread"

# Source and target
SOURCE="sharded_server_phase8_step23_io_uring_fixed.cpp"
TARGET="meteor_phase8_step23_io_uring_key_routing_fixed"

# Build command
BUILD_CMD="$CXX $CXXFLAGS -o $TARGET $SOURCE $LIBS"

echo "🔧 Build command: $BUILD_CMD"
echo ""

# Execute build
if $BUILD_CMD; then
    echo ""
    echo "✅ BUILD SUCCESSFUL!"
    echo ""
    echo "🎯 **HYBRID EPOLL + IO_URING SERVER READY**"
    echo ""
    echo "📊 **EXPECTED RELIABLE PERFORMANCE:**"
    echo "   🚀 Target: 4M+ RPS (incremental improvement)"
    echo "   ⚡ P99 Latency: <1ms (proven baseline + async boost)"
    echo "   🔒 Reliability: Zero connection resets (proven epoll accepts)"
    echo "   ⚡ Async I/O: Optional io_uring recv/send acceleration"
    echo ""
    echo "🏃‍♂️ **READY TO TEST:**"
    echo "   ./meteor_phase8_step23_io_uring_key_routing_fixed -h 127.0.0.1 -p 6380 -c 4"
    echo ""
    echo "🎯 **ARCHITECTURE HIGHLIGHTS:**"
    echo "   • Proven epoll accepts (no SQPOLL complications)"
    echo "   • Optional io_uring for recv/send operations"
    echo "   • Automatic fallback to sync I/O if needed"
    echo "   • True shared-nothing: per-core isolation"
    echo "   • Gradual async migration for reliability"
    echo ""
    echo "🏆 **MISSION: Reliable performance boost with io_uring!**"
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
