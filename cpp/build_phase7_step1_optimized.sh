#!/bin/bash

echo "=== 🚀 BUILDING OPTIMIZED io_uring SERVER (Phase 6 Step 3 + io_uring) 🚀 ==="
echo "🎯 Target: Beat DragonflyDB performance (1.5M+ RPS)"
echo "⚡ Architecture: Pure io_uring + ALL Phase 6 Step 3 optimizations"
echo ""

# Check OS type
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "❌ macOS not supported for pure io_uring implementation"
    echo "💡 io_uring is Linux-specific. Use Linux or WSL for testing."
    exit 1
else
    echo "✅ Building for Linux (optimized io_uring)..."
    
    # Check if liburing is available
    if pkg-config --exists liburing 2>/dev/null; then
        echo "✅ liburing found - building optimized io_uring server..."
        
        # Get liburing version
        LIBURING_VERSION=$(pkg-config --modversion liburing)
        echo "📦 liburing version: $LIBURING_VERSION"
        
        # Build with all optimizations (Phase 6 Step 3 + io_uring)
        g++ -std=c++17 -O3 -march=native -mavx2 -mavx512f \
            -DHAS_LINUX_EPOLL=0 \
            -DHAS_IO_URING=1 \
            -I. \
            sharded_server_phase7_step1_optimized_iouring.cpp \
            -o meteor_optimized_iouring \
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
    echo "✅ Optimized io_uring server compiled successfully"
    ls -la meteor_optimized_iouring
    echo ""
    echo "🏗️  Architecture Features:"
    echo "   ✅ Pure io_uring (NO epoll fallback)"
    echo "   ✅ ALL Phase 6 Step 3 optimizations preserved:"
    echo "      - Pipeline batch processing"
    echo "      - CPU affinity & multi-accept"
    echo "      - SIMD & AVX-512 optimizations"  
    echo "      - SSD cache & hybrid storage"
    echo "      - Advanced monitoring"
    echo "      - Connection migration"
    echo "   ✅ DragonflyDB-style async I/O"
    echo "   ✅ Optimized network I/O"
    echo ""
    echo "🚀 Ready to beat DragonflyDB performance!"
    echo "💡 Usage: ./meteor_optimized_iouring -h 127.0.0.1 -p 6379 -c 4"
else
    echo ""
    echo "❌ BUILD FAILED!"
    echo "💡 Check the error messages above for details"
    exit 1
fi