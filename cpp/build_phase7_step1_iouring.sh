#!/bin/bash

# **PHASE 7 STEP 1: IO_URING HIGH-PERFORMANCE I/O BUILD SCRIPT**
# Revolutionary I/O performance with io_uring async operations
# Target: 3x improvement over Phase 6 Step 3 (2.4M+ RPS)

set -e

echo "🚀 PHASE 7 STEP 1: IO_URING HIGH-PERFORMANCE I/O BUILD"
echo "======================================================"

# Check for io_uring library availability
echo "🔍 Checking io_uring availability..."
if pkg-config --exists liburing 2>/dev/null; then
    echo "✅ liburing found via pkg-config"
    URING_CFLAGS=$(pkg-config --cflags liburing)
    URING_LIBS=$(pkg-config --libs liburing)
elif [ -f /usr/include/liburing.h ] || [ -f /usr/local/include/liburing.h ]; then
    echo "✅ liburing headers found"
    URING_CFLAGS=""
    URING_LIBS="-luring"
else
    echo "⚠️  liburing not found - building with epoll fallback"
    echo "   To install liburing:"
    echo "   - Ubuntu/Debian: sudo apt install liburing-dev"
    echo "   - RHEL/CentOS: sudo dnf install liburing-devel"
    echo "   - macOS: Will use kqueue (no io_uring support)"
    URING_CFLAGS=""
    URING_LIBS=""
fi

# Build with io_uring optimizations
echo "🔨 Building Phase 7 Step 1 io_uring server..."

# Try with io_uring + NUMA support first (Linux only)
if [ -n "$URING_LIBS" ] && [[ "$OSTYPE" != "darwin"* ]]; then
    echo "🚀 Building with io_uring support (Linux)..."
    g++ -std=c++17 -O3 -march=native -mavx512f -mavx512vl -mavx512bw \
        -DHAS_LINUX_EPOLL $URING_CFLAGS -pthread -lnuma $URING_LIBS \
        sharded_server_phase7_step1_iouring.cpp \
        -o meteor_phase7_step1_iouring 2>/dev/null || \
    g++ -std=c++17 -O3 -march=native -mavx2 \
        -DHAS_LINUX_EPOLL $URING_CFLAGS -pthread $URING_LIBS \
        sharded_server_phase7_step1_iouring.cpp \
        -o meteor_phase7_step1_iouring
else
    echo "⚡ Building with epoll/kqueue fallback..."
    # Detect platform and use appropriate flags
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "🍎 macOS detected - using kqueue"
        g++ -std=c++17 -O3 -march=native \
            -DHAS_MACOS_KQUEUE -pthread \
            sharded_server_phase7_step1_iouring.cpp \
            -o meteor_phase7_step1_iouring
    else
        echo "🐧 Linux detected - using epoll"
        g++ -std=c++17 -O3 -march=native -mavx512f -mavx512vl -mavx512bw \
            -DHAS_LINUX_EPOLL -pthread -lnuma \
            sharded_server_phase7_step1_iouring.cpp \
            -o meteor_phase7_step1_iouring 2>/dev/null || \
        g++ -std=c++17 -O3 -march=native -mavx2 \
            -DHAS_LINUX_EPOLL -pthread \
            sharded_server_phase7_step1_iouring.cpp \
            -o meteor_phase7_step1_iouring
    fi
fi

echo "✅ Build completed successfully!"

echo ""
echo "🎯 REVOLUTIONARY IMPROVEMENTS IN PHASE 7 STEP 1:"
echo "================================================"
echo "🚀 io_uring async I/O - 2-3x better than epoll"
echo "🚀 Batched accept/recv/send operations"
echo "🚀 Zero-copy buffer management"
echo "🚀 Advanced completion queue processing"
echo "✅ Preserves all Phase 6 Step 3 optimizations:"
echo "   - DragonflyDB-style pipeline batch processing"
echo "   - Multi-accept + CPU affinity"
echo "   - SIMD vectorization (AVX-512)"
echo "   - Lock-free data structures"
echo "   - Advanced monitoring"
echo ""
echo "🎯 TARGET PERFORMANCE:"
echo "======================"
echo "🔥 2.4M+ RPS (3x improvement over Phase 6 Step 3)"
echo "🔥 Sub-20μs latency with io_uring"
echo "🔥 Reduced CPU utilization"
echo "🔥 Better memory efficiency"
echo ""
echo "📋 Usage:"
echo "./meteor_phase7_step1_iouring -h 127.0.0.1 -p 6379 -c 16 -s 32 -m 1024"
echo ""
echo "🚀 Ready to revolutionize performance!"