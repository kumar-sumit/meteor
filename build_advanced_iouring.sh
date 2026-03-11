#!/bin/bash

# **ADVANCED io_uring BUILD SCRIPT with latest liburing**
echo "=== 🚀 BUILDING ADVANCED io_uring SERVER (Latest liburing) 🚀 ==="
echo "🎯 Target: Beat DragonflyDB performance with advanced io_uring"
echo "⚡ Architecture: Phase 6 Step 3 + Advanced io_uring optimizations"
echo "🏗️  Features: SQPOLL, Fixed buffers, Multi-shot, Zero-copy"
echo ""

# Check liburing version
LIBURING_VERSION=$(pkg-config --modversion liburing 2>/dev/null || echo "unknown")
echo "📦 liburing version: $LIBURING_VERSION"

# Determine compiler and flags
if command -v g++ >/dev/null 2>&1; then
    COMPILER="g++"
    echo "✅ Using g++ compiler"
elif command -v clang++ >/dev/null 2>&1; then
    COMPILER="clang++"
    echo "✅ Using clang++ compiler"
else
    echo "❌ No suitable C++ compiler found"
    exit 1
fi

# Advanced compiler flags for maximum performance
CXXFLAGS="-std=c++17 -O3 -march=native -mtune=native"
CXXFLAGS="$CXXFLAGS -flto -ffast-math -funroll-loops"
CXXFLAGS="$CXXFLAGS -DHAS_LINUX_EPOLL -DHAS_IO_URING"
CXXFLAGS="$CXXFLAGS -mavx2 -mavx512f -mavx512dq -mavx512bw -mavx512vl"
CXXFLAGS="$CXXFLAGS -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare"

# Try to find liburing
LIBURING_LIBS=""
LIBURING_INCLUDES=""

# Check standard locations
if pkg-config --exists liburing; then
    LIBURING_LIBS=$(pkg-config --libs liburing)
    LIBURING_INCLUDES=$(pkg-config --cflags liburing)
    echo "✅ Found liburing via pkg-config"
elif [ -f "/usr/local/lib/liburing.so" ]; then
    LIBURING_LIBS="-L/usr/local/lib -luring"
    LIBURING_INCLUDES="-I/usr/local/include"
    echo "✅ Found liburing in /usr/local"
elif [ -f "/usr/lib/x86_64-linux-gnu/liburing.so" ]; then
    LIBURING_LIBS="-luring"
    LIBURING_INCLUDES=""
    echo "✅ Found liburing in system paths"
else
    echo "❌ liburing not found! Please install liburing-dev or run upgrade script"
    exit 1
fi

# Build command
BUILD_CMD="$COMPILER $CXXFLAGS $LIBURING_INCLUDES \
    -o meteor_advanced_iouring \
    sharded_server_phase7_step1_incremental_complete.cpp \
    $LIBURING_LIBS -lpthread"

echo ""
echo "🔨 Build command:"
echo "$BUILD_CMD"
echo ""

# Execute build
echo "🏗️  Building advanced io_uring server..."
if $BUILD_CMD; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL! 🎉"
    echo "✅ Advanced io_uring server compiled successfully"
    ls -la meteor_advanced_iouring
    
    echo ""
    echo "🏗️  Binary information:"
    file meteor_advanced_iouring
    echo ""
    
    echo "🔍 Checking for io_uring symbols:"
    if command -v nm >/dev/null 2>&1; then
        echo "io_uring functions found:"
        nm meteor_advanced_iouring | grep io_uring | head -10
    fi
    
    echo ""
    echo "🚀 Ready to test! Usage examples:"
    echo "  Basic io_uring:     METEOR_USE_IO_URING=1 ./meteor_advanced_iouring -h 127.0.0.1 -p 6379 -c 4"
    echo "  SQPOLL mode:        METEOR_USE_IO_URING=1 METEOR_USE_SQPOLL=1 ./meteor_advanced_iouring -h 127.0.0.1 -p 6379 -c 4"
    echo "  Ultimate config:    METEOR_USE_IO_URING=1 METEOR_USE_SQPOLL=1 METEOR_USE_MULTISHOT=1 ./meteor_advanced_iouring -h 127.0.0.1 -p 6379 -c 4"
    
else
    echo ""
    echo "❌ BUILD FAILED!"
    echo "💡 Check the error messages above for details"
    echo "💡 Make sure liburing is properly installed"
    exit 1
fi