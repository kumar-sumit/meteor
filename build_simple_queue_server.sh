#!/bin/bash

# **BUILD SIMPLE QUEUE SERVER**
# Keep it simple, get it working first, optimize later

echo "🔧 BUILDING SIMPLE QUEUE SERVER"
echo "==============================="
echo "Philosophy: Simple queues, sequential processing, working baseline"
echo "No complex fibers, no promises/futures, no async complexity"
echo ""

# Configuration
SOURCE_FILE="sharded_server_simple_queue_approach.cpp"
BINARY_NAME="simple_queue_server"
BUILD_DIR="."

echo "📂 Build directory: $BUILD_DIR"
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

echo "🔨 COMPILING SIMPLE SERVER..."
echo "============================"

# Simple compilation - no complex dependencies
g++ -std=c++17 -O3 -DNDEBUG \
    -Wall -Wextra -Wno-unused-parameter \
    -pthread \
    $SOURCE_FILE \
    -o $BINARY_NAME \
    -lpthread \
    2>&1

compilation_result=$?

if [ $compilation_result -eq 0 ]; then
    echo ""
    echo "✅ COMPILATION SUCCESSFUL!"
    echo "========================="
    
    if [ -f "$BINARY_NAME" ]; then
        echo "📦 Binary created: $BUILD_DIR/$BINARY_NAME"
        echo "📏 Binary size: $(du -h $BINARY_NAME | cut -f1)"
        
        echo ""
        echo "🎯 SIMPLE QUEUE SERVER READY"
        echo "============================"
        echo "✅ No complex dependencies (just pthread)"
        echo "✅ No fiber complexity"
        echo "✅ No promise/future deadlocks" 
        echo "✅ Simple sequential processing"
        echo ""
        echo "🧪 Ready for testing:"
        echo "   ./$BINARY_NAME -c 4 -p 6379"
        echo ""
        echo "📊 Expected improvements:"
        echo "   - ❌ Before: 0 ops/sec (broken fiber processing)"
        echo "   - ✅ After: Actual command processing should work"
        echo "   - 🎯 Goal: Get SOME working throughput, then optimize"
        
    else
        echo "❌ Binary not created despite successful compilation"
        exit 1
    fi
    
else
    echo ""
    echo "❌ COMPILATION FAILED"
    echo "===================="
    echo "Exit code: $compilation_result"
    exit $compilation_result
fi

echo ""
echo "🏆 SIMPLE APPROACH READY FOR VM TESTING"
echo "========================================"
echo "Next steps:"
echo "1. Copy to VM: gcloud compute scp ..."
echo "2. Test basic functionality"
echo "3. Verify commands actually process"
echo "4. Add optimizations incrementally"














