#!/bin/bash

# **BUILD TIMEOUT-FIXED INTEGRATED SERVER**
# Fix for the 100ms timeout regression causing "-ERR timeout" responses

echo "🔧 BUILDING TIMEOUT-FIXED INTEGRATED SERVER"
echo "==========================================="
echo "🐛 REGRESSION FIX: 100ms timeout → 5000ms timeout"
echo "📊 Expected improvement: 9 ops/sec → 100K+ ops/sec"
echo ""

# Configuration
SOURCE_FILE="sharded_server_phase8_step25_io_uring_boost_fiber_integrated.cpp"
BINARY_NAME="integrated_temporal_coherence_server_fixed"
BUILD_DIR="/tmp/temporal_build_fix"

# Create build directory
mkdir -p $BUILD_DIR
cd $BUILD_DIR

echo "📂 Build directory: $BUILD_DIR"
echo "📄 Source file: $SOURCE_FILE"
echo "🎯 Target binary: $BINARY_NAME"
echo ""

# Check source file exists
if [ ! -f "../../../cpp/$SOURCE_FILE" ]; then
    echo "❌ Source file not found: ../../../cpp/$SOURCE_FILE"
    exit 1
fi

echo "🔍 Checking Boost.Fibers availability..."
if pkg-config --exists libfiber 2>/dev/null; then
    echo "✅ Boost.Fibers found via pkg-config"
    FIBER_CFLAGS=$(pkg-config --cflags libfiber)
    FIBER_LIBS=$(pkg-config --libs libfiber)
elif [ -d "/usr/include/boost/fiber" ] || [ -d "/usr/local/include/boost/fiber" ]; then
    echo "✅ Boost.Fibers headers found"
    FIBER_CFLAGS="-I/usr/include -I/usr/local/include"
    FIBER_LIBS="-lboost_fiber -lboost_context -lboost_system"
else
    echo "⚠️  Boost.Fibers headers not found, continuing with basic flags"
    FIBER_CFLAGS=""
    FIBER_LIBS="-lboost_fiber -lboost_context -lboost_system"
fi

echo "🔗 Checking liburing availability..."
if pkg-config --exists liburing 2>/dev/null; then
    echo "✅ liburing found via pkg-config"
    URING_CFLAGS=$(pkg-config --cflags liburing)
    URING_LIBS=$(pkg-config --libs liburing)
elif [ -f "/usr/include/liburing.h" ] || [ -f "/usr/local/include/liburing.h" ]; then
    echo "✅ liburing headers found"
    URING_CFLAGS="-I/usr/include -I/usr/local/include"
    URING_LIBS="-luring"
else
    echo "⚠️  liburing not found, will disable io_uring features"
    URING_CFLAGS="-DNO_URING"
    URING_LIBS=""
fi

echo ""
echo "🔨 COMPILING WITH TIMEOUT FIX..."
echo "================================="

# Compile with comprehensive flags
g++ -std=c++17 -O3 -DNDEBUG \
    -Wall -Wextra -Wno-unused-parameter \
    $FIBER_CFLAGS $URING_CFLAGS \
    -I../../../include \
    -pthread \
    ../../../cpp/$SOURCE_FILE \
    -o $BINARY_NAME \
    $FIBER_LIBS $URING_LIBS \
    -lpthread \
    -latomic \
    2>&1

compilation_result=$?

if [ $compilation_result -eq 0 ]; then
    echo ""
    echo "✅ COMPILATION SUCCESSFUL!"
    echo "========================="
    
    # Verify binary
    if [ -f "$BINARY_NAME" ]; then
        echo "📦 Binary created: $BUILD_DIR/$BINARY_NAME"
        echo "📏 Binary size: $(du -h $BINARY_NAME | cut -f1)"
        
        # Check dependencies
        echo ""
        echo "🔗 Checking dependencies..."
        if command -v ldd >/dev/null 2>&1; then
            echo "Dependencies:"
            ldd $BINARY_NAME | grep -E "(boost|uring|fiber)" || echo "  No special dependencies found"
        fi
        
        echo ""
        echo "🎯 TIMEOUT-FIXED SERVER READY FOR TESTING"
        echo "=========================================="
        echo "Binary location: $BUILD_DIR/$BINARY_NAME"
        echo ""
        echo "📊 Expected improvements:"
        echo "   - ❌ Before: ~9 ops/sec with '-ERR timeout'"  
        echo "   - ✅ After: 100K+ ops/sec with proper responses"
        echo ""
        echo "🧪 Next steps:"
        echo "   1. Copy binary to VM"
        echo "   2. Run memtier_benchmark test"
        echo "   3. Verify timeout elimination"
        
    else
        echo "❌ Binary not created despite successful compilation"
        exit 1
    fi
    
else
    echo ""
    echo "❌ COMPILATION FAILED"
    echo "===================="
    echo "Exit code: $compilation_result"
    echo ""
    echo "🔧 Common issues:"
    echo "   - Missing Boost.Fibers development headers"
    echo "   - Missing liburing development headers" 
    echo "   - Incompatible compiler version"
    echo ""
    echo "💡 Try installing dependencies:"
    echo "   sudo apt install libboost-fiber-dev liburing-dev"
    exit $compilation_result
fi














