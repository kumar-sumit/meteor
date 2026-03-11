#!/bin/bash

echo "=== 🚀 BUILDING CLEAN io_uring SERVER (Phase 7 Step 1) 🚀 ==="
echo "🎯 Target: Beat DragonflyDB performance (1.5M+ RPS)"
echo "⚡ Architecture: Pure io_uring + Phase 6 Step 3 optimizations"
echo "🏗️  Features: Pipeline batching, CPU affinity, SIMD, clean codebase"
echo ""

# Check OS type
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "❌ macOS not supported for pure io_uring implementation"
    echo "💡 io_uring is Linux-specific. Use Linux or WSL for testing."
    exit 1
else
    echo "✅ Building for Linux (clean io_uring implementation)..."
    
    # Check if liburing is available
    if pkg-config --exists liburing 2>/dev/null; then
        echo "✅ liburing found - building clean io_uring server..."
        
        # Get liburing version
        LIBURING_VERSION=$(pkg-config --modversion liburing)
        echo "📦 liburing version: $LIBURING_VERSION"
        
        # Build with all optimizations (clean implementation)
        g++ -std=c++17 -O3 -march=native -mavx2 \
            -Wall -Wextra -Wpedantic \
            -I. \
            sharded_server_phase7_step1_clean_iouring.cpp \
            -o meteor_clean_iouring \
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
    echo "✅ Clean io_uring server compiled successfully"
    ls -la meteor_clean_iouring
    echo ""
    echo "🏗️  Architecture Features:"
    echo "   ✅ Pure io_uring (NO epoll fallback)"
    echo "   ✅ Phase 6 Step 3 optimizations:"
    echo "      - Pipeline batch processing"
    echo "      - CPU affinity per core"
    echo "      - SIMD optimizations"
    echo "      - Advanced monitoring"
    echo "   ✅ DragonflyDB-style async I/O"
    echo "   ✅ Clean, maintainable codebase"
    echo ""
    echo "🚀 Ready to beat DragonflyDB performance!"
    echo "💡 Usage: ./meteor_clean_iouring -h 127.0.0.1 -p 6379 -c 4"
else
    echo ""
    echo "❌ BUILD FAILED!"
    echo "💡 Check the error messages above for details"
    exit 1
fi