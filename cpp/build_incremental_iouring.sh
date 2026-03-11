#!/bin/bash

echo "=== 🚀 BUILDING INCREMENTAL io_uring SERVER (Phase 6 Step 3 + io_uring) 🚀 ==="
echo "🎯 Target: Beat DragonflyDB performance (1.5M+ RPS)"
echo "⚡ Architecture: ALL Phase 6 Step 3 optimizations + optional io_uring"
echo "🏗️  Features: Pipeline batching, CPU affinity, SIMD, SSD cache, monitoring, etc."
echo "🔧 Testing: Use METEOR_USE_IO_URING=1 to enable io_uring mode"
echo ""

# Check OS type
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "❌ macOS not supported for io_uring implementation"
    echo "💡 io_uring is Linux-specific. Use Linux or WSL for testing."
    exit 1
else
    echo "✅ Building for Linux (incremental io_uring implementation)..."
    
    # Check if liburing is available
    if pkg-config --exists liburing 2>/dev/null; then
        echo "✅ liburing found - building incremental io_uring server..."
        
        # Get liburing version
        LIBURING_VERSION=$(pkg-config --modversion liburing)
        echo "📦 liburing version: $LIBURING_VERSION"
        
        # Build with all optimizations (Phase 6 Step 3 + io_uring)
        g++ -std=c++17 -O3 -march=native -mavx2 -mavx512f \
            -DHAS_LINUX_EPOLL=1 \
            -Wall -Wextra \
            -I. \
            sharded_server_phase7_step1_incremental_complete.cpp \
            -o meteor_incremental_iouring \
            $(pkg-config --cflags --libs liburing) \
            -lpthread
            
    else
        echo "❌ liburing not found!"
        echo ""
        echo "📋 Installation instructions:"
        echo "   Ubuntu/Debian: sudo apt-get install liburing-dev"
        echo "   CentOS/RHEL:   sudo yum install liburing-devel"
        echo "   Fedora:        sudo dnf install liburing-devel"
        exit 1
    fi
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL! 🎉"
    echo "✅ Incremental io_uring server compiled successfully"
    ls -la meteor_incremental_iouring
    echo ""
    echo "🏗️  Architecture Features:"
    echo "   ✅ ALL Phase 6 Step 3 optimizations preserved:"
    echo "      - True batch pipeline processing"
    echo "      - Single response buffer per connection"
    echo "      - Pipeline-aware connection migration"
    echo "      - Enhanced monitoring for pipeline metrics"
    echo "      - Multi-accept + CPU affinity with SO_REUSEPORT"
    echo "      - SIMD & AVX-512 optimizations"
    echo "      - SSD cache & hybrid storage"
    echo "      - Advanced bottleneck detection"
    echo "   ✅ NEW: Optional io_uring support (DragonflyDB style)"
    echo "      - Runtime switchable with METEOR_USE_IO_URING=1"
    echo "      - Batched I/O operations"
    echo "      - Minimal syscall overhead"
    echo ""
    echo "🚀 Ready to test both epoll and io_uring modes!"
    echo "💡 Usage:"
    echo "   Epoll mode:    ./meteor_incremental_iouring -h 127.0.0.1 -p 6379 -c 4"
    echo "   io_uring mode: METEOR_USE_IO_URING=1 ./meteor_incremental_iouring -h 127.0.0.1 -p 6379 -c 4"
else
    echo ""
    echo "❌ BUILD FAILED!"
    echo "💡 Check the error messages above for details"
    exit 1
fi