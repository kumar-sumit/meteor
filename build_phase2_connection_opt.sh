#!/bin/bash

# **BUILD PHASE 2 CONNECTION OPTIMIZED SERVER**
# Building on 1.32M QPS success with connection management optimizations

echo "🚀 BUILDING PHASE 2 CONNECTION OPTIMIZED SERVER"
echo "==============================================="
echo "Building on: 1.32M QPS incremental optimization success"
echo "Target: 2.5M+ QPS (90% improvement)"
echo "Focus: Connection management optimizations"
echo ""
echo "Phase 2 Optimizations:"
echo "  ✅ Keep-alive connections (connection reuse)"
echo "  ✅ Batched accept operations (reduced epoll overhead)"
echo "  ✅ Per-connection buffers (reduced allocations)"
echo "  ✅ TCP optimizations (NODELAY, KEEPALIVE)"
echo "  ✅ Connection state management"
echo ""

# Configuration
SOURCE_FILE="sharded_server_phase2_connection_opt.cpp"
BINARY_NAME="phase2_connection_opt_server"

echo "📄 Source file: $SOURCE_FILE"
echo "🎯 Target binary: $BINARY_NAME"
echo ""

# Check source file
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Source file not found: $SOURCE_FILE"
    exit 1
fi

echo "✅ Source file found"
echo ""

# Clean up any previous builds
rm -f *.o phase2_connection_opt_server 2>/dev/null

echo "🔨 COMPILING PHASE 2 CONNECTION SERVER..."
echo "========================================"

# Proven compilation flags that worked for 1.32M QPS
TMPDIR=/dev/shm g++ -std=c++17 -O2 -DNDEBUG \
    -Wall -Wextra -Wno-unused-parameter \
    -pthread \
    $SOURCE_FILE \
    -o $BINARY_NAME \
    -lpthread \
    2>&1

compilation_result=$?

if [ $compilation_result -eq 0 ]; then
    echo ""
    echo "✅ PHASE 2 CONNECTION BUILD SUCCESSFUL!"
    echo "====================================="
    
    if [ -f "$BINARY_NAME" ]; then
        echo "📦 Binary created: ./$BINARY_NAME"
        echo "📏 Binary size: $(du -h $BINARY_NAME | cut -f1)"
        
        echo ""
        echo "🎯 PHASE 2 CONNECTION OPTIMIZATIONS:"
        echo "==================================="
        echo "✅ All Phase 1 optimizations preserved (1.32M QPS baseline)"
        echo "✅ + Connection keep-alive and reuse"
        echo "✅ + Batched accept() operations"  
        echo "✅ + Per-connection buffer management"
        echo "✅ + TCP_NODELAY and SO_KEEPALIVE"
        echo "✅ + Connection state tracking"
        echo "✅ + Connection cleanup and timeout handling"
        echo ""
        echo "Expected: 90% improvement (2.5M+ QPS target)"
        
        echo ""
        echo "🧪 READY FOR PHASE 2 TESTING:"
        echo "============================="
        echo "Launch: ./$BINARY_NAME -c 4 -p 9000"
        echo "Test: memtier_benchmark -s 127.0.0.1 -p 9000 -c 16 -t 8 --pipeline=15 -n 10000"
        echo ""
        echo "📊 Expected results:"
        echo "   - Phase 1 baseline: 1.32M QPS"
        echo "   - Phase 2 target: 2.5M+ QPS"
        echo "   - Connection reuse metrics available"
        
    else
        echo "❌ Binary not created"
        exit 1
    fi
    
else
    echo ""
    echo "❌ PHASE 2 CONNECTION BUILD FAILED"
    echo "=================================="
    echo "Exit code: $compilation_result"
    exit $compilation_result
fi

echo ""
echo "🎊 PHASE 2 CONNECTION OPTIMIZED SERVER READY!"
echo "============================================="
echo "Ready to test path from 1.32M → 2.5M+ QPS"














