#!/bin/bash

# **BUILD INCREMENTAL OPTIMIZED SERVER**
# One small optimization at a time - test each change

echo "🔧 BUILDING INCREMENTAL OPTIMIZED SERVER"
echo "========================================"
echo "Strategy: One optimization at a time, measure each change"
echo "Baseline: Simple queue server (800K QPS)"
echo "Target: 1M+ QPS (25% improvement)"
echo ""
echo "Current optimization: Reduced system calls"
echo ""

# Configuration
SOURCE_FILE="sharded_server_incremental_opt.cpp"
BINARY_NAME="incremental_opt_server"

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
rm -f *.o incremental_opt_server 2>/dev/null

echo "🔨 COMPILING INCREMENTAL SERVER..."
echo "================================="

# Simple, proven compilation flags
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
    echo "✅ INCREMENTAL BUILD SUCCESSFUL!"
    echo "==============================="
    
    if [ -f "$BINARY_NAME" ]; then
        echo "📦 Binary created: ./$BINARY_NAME"
        echo "📏 Binary size: $(du -h $BINARY_NAME | cut -f1)"
        
        echo ""
        echo "🎯 INCREMENTAL CHANGES:"
        echo "======================"
        echo "✅ Same as baseline (proven 800K QPS)"
        echo "✅ + Pre-calculated response buffer sizes"
        echo "✅ + Single write() calls instead of multiple sends"  
        echo "✅ + String capacity pre-allocation"
        echo ""
        echo "Expected: 10-25% improvement (880K-1M QPS)"
        
        echo ""
        echo "🧪 READY FOR INCREMENTAL TESTING:"
        echo "================================="
        echo "Launch: ./$BINARY_NAME -c 4 -p 8000"
        echo "Test: memtier_benchmark -s 127.0.0.1 -p 8000 -c 8 -t 8 --pipeline=10 -n 10000"
        
    else
        echo "❌ Binary not created"
        exit 1
    fi
    
else
    echo ""
    echo "❌ INCREMENTAL BUILD FAILED"
    echo "=========================="
    echo "Exit code: $compilation_result"
    exit $compilation_result
fi

echo ""
echo "✅ INCREMENTAL OPTIMIZED SERVER READY"














