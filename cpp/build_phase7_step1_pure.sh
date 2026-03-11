#!/bin/bash

echo "=== 🚀 BUILDING PURE io_uring SERVER (DragonflyDB Style) 🚀 ==="
echo "🎯 Target: Beat DragonflyDB performance (1.5M+ RPS)"
echo "⚡ Architecture: Pure io_uring, NO epoll/kqueue fallback"
echo ""

# Detect OS type
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "❌ macOS not supported for pure io_uring implementation"
    echo "💡 io_uring is Linux-specific. Use Linux or WSL for testing."
    exit 1
else
    echo "✅ Building for Linux (pure io_uring)..."
    
    # Check if liburing is available
    if pkg-config --exists liburing 2>/dev/null; then
        echo "✅ liburing found - building pure io_uring server..."
        
        # Get liburing version
        LIBURING_VERSION=$(pkg-config --modversion liburing)
        echo "📦 liburing version: $LIBURING_VERSION"
        
        # Build with optimizations
        g++ -std=c++17 -O3 -march=native \
            -DHAS_LINUX_EPOLL=0 \
            -DHAS_IO_URING=1 \
            -I. \
            sharded_server_phase7_step1_pure_iouring.cpp \
            -o meteor_pure_iouring \
            $(pkg-config --cflags --libs liburing) \
            -lpthread
            
    else
        echo "❌ liburing not found!"
        echo ""
        echo "📋 Installation instructions:"
        echo "   Ubuntu/Debian: sudo apt-get install liburing-dev"
        echo "   CentOS/RHEL:   sudo yum install liburing-devel"
        echo "   Fedora:        sudo dnf install liburing-devel"
        echo ""
        echo "💡 Or build from source:"
        echo "   git clone https://github.com/axboe/liburing.git"
        echo "   cd liburing && make && sudo make install"
        exit 1
    fi
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 BUILD SUCCESSFUL! 🎉"
    echo "✅ Pure io_uring server compiled successfully"
    ls -la meteor_pure_iouring
    echo ""
    echo "🏗️  Architecture Features:"
    echo "   ✅ Pure io_uring (NO epoll fallback)"
    echo "   ✅ Thread-per-core model"
    echo "   ✅ Shared-nothing architecture"
    echo "   ✅ Batch operations"
    echo "   ✅ CPU affinity"
    echo "   ✅ Optimized command processing"
    echo ""
    echo "🚀 Ready to test against DragonflyDB!"
    echo "💡 Usage: ./meteor_pure_iouring -h 127.0.0.1 -p 6379 -c 4"
else
    echo ""
    echo "❌ BUILD FAILED!"
    echo "💡 Check the error messages above for details"
    exit 1
fi