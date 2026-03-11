#!/bin/bash

# **PHASE 7 STEP 2: Build Script for DragonflyDB-Style Unlimited Key Storage Server**
# This script builds the new implementation with unlimited key storage and true shared-nothing architecture

echo "🚀 Building Phase 7 Step 2: DragonflyDB-Style Unlimited Key Storage Server"
echo "============================================================================="

# Set build parameters (ARM64/Apple Silicon compatible)
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    echo "🔧 Detected ARM64 architecture (Apple Silicon)"
    CXX_FLAGS="-std=c++17 -O3 -march=native -DHAS_MACOS_KQUEUE -pthread"
else
    echo "🔧 Detected x86_64 architecture"
    CXX_FLAGS="-std=c++17 -O3 -march=native -DAVX512_ENABLED -mavx2 -mavx512f -mavx512vl -mavx512bw -mavx512dq -mavx512cd -msse4.2 -DHAS_LINUX_EPOLL -pthread"
fi
SOURCE_FILE="sharded_server_phase7_step2_dragonfly_unlimited.cpp"
OUTPUT_BINARY="meteor_dragonfly_unlimited"

echo "🔧 Compilation settings:"
echo "   Source: $SOURCE_FILE"
echo "   Output: $OUTPUT_BINARY"
echo "   Flags: $CXX_FLAGS"
echo ""

# Compile the server
echo "⚙️ Compiling..."
if [[ "$ARCH" == "arm64" ]]; then
    clang++ $CXX_FLAGS $SOURCE_FILE -o $OUTPUT_BINARY
else
    g++ $CXX_FLAGS $SOURCE_FILE -o $OUTPUT_BINARY
fi

# Check compilation result
if [ $? -eq 0 ]; then
    echo "✅ Compilation successful!"
    echo ""
    echo "📊 Binary information:"
    ls -lh $OUTPUT_BINARY
    echo ""
    echo "🎯 Key Features Implemented:"
    echo "   ✅ DragonflyDB-Style Dashtable with 56 regular + 4 stash buckets per segment"
    echo "   ✅ FreeCache-Inspired Ring Buffer Memory Management (Zero GC)"
    echo "   ✅ Dynamic Segment Growth for Unlimited Key Storage"
    echo "   ✅ True Shared-Nothing Architecture (Each shard owns its data)"
    echo "   ✅ Intelligent Command Routing with MOVED responses"
    echo "   ✅ Memory-Efficient Key Distribution across available RAM"
    echo "   ✅ TB-Scale Support with Linear Memory Scaling"
    echo ""
    echo "🚀 Ready to test unlimited key storage capabilities!"
    echo "   Usage: ./$OUTPUT_BINARY -h 127.0.0.1 -p 6379 -c <cores>"
    echo ""
    echo "📈 Performance Expectations:"
    echo "   • Unlimited key storage (limited only by available RAM)"
    echo "   • Sub-millisecond latency for key operations"
    echo "   • Linear scaling with available memory"
    echo "   • 1M+ RPS sustained throughput with large datasets"
    echo "   • Zero GC overhead for key storage operations"
else
    echo "❌ Compilation failed!"
    echo "Please check the error messages above and fix any issues."
    exit 1
fi