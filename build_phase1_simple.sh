#!/bin/bash

# **BUILD PHASE 1 OPTIMIZED SERVER - SIMPLE VERSION**
# Fallback build without aggressive optimizations to avoid disk space issues

echo "🔧 BUILDING PHASE 1 OPTIMIZED SERVER (Simple Build)"
echo "===================================================="
echo "Target: 2M+ QPS with reduced build complexity"
echo ""

# Configuration
SOURCE_FILE="sharded_server_phase1_optimized.cpp"
BINARY_NAME="phase1_optimized_server"

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

# Clean up any previous build artifacts to free space
rm -f *.o *.s phase1_optimized_server 2>/dev/null

echo "🔨 COMPILING WITH SIMPLE FLAGS..."
echo "================================="

# Simplified compilation flags to avoid space issues
g++ -std=c++17 -O2 -DNDEBUG \
    -Wall -Wextra -Wno-unused-parameter \
    -pthread \
    -march=native \
    $SOURCE_FILE \
    -o $BINARY_NAME \
    -lpthread \
    -latomic \
    2>&1

compilation_result=$?

if [ $compilation_result -eq 0 ]; then
    echo ""
    echo "✅ SIMPLE BUILD SUCCESSFUL!"
    echo "=========================="
    
    if [ -f "$BINARY_NAME" ]; then
        echo "📦 Binary created: ./$BINARY_NAME"
        echo "📏 Binary size: $(du -h $BINARY_NAME | cut -f1)"
        
        echo ""
        echo "🎯 OPTIMIZATIONS INCLUDED:"
        echo "========================="
        echo "✅ Memory Pools: Pre-allocated object pools"
        echo "✅ Zero-Copy Parsing: String views for RESP"
        echo "✅ Lock-Free Queues: Atomic ring buffers"
        echo "✅ Optimized Cache: Better hash table"
        echo "✅ CPU-Specific: -march=native optimization"
        
        echo ""
        echo "🧪 READY FOR TESTING:"
        echo "==================="
        echo "Launch: ./$BINARY_NAME -c 4 -p 7000"
        echo "Test: memtier_benchmark -s 127.0.0.1 -p 7000 -c 8 -t 8 --pipeline=10 -n 10000"
        
    else
        echo "❌ Binary not created"
        exit 1
    fi
    
else
    echo ""
    echo "❌ SIMPLE BUILD FAILED"
    echo "===================="
    echo "Exit code: $compilation_result"
    exit $compilation_result
fi

echo ""
echo "✅ PHASE 1 OPTIMIZED SERVER READY (Simple Build)"














