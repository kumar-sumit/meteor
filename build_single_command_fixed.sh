#!/bin/bash

# Build script for Meteor v7.0 Single Command Correctness server

echo "🔨 Building Meteor v7.0 - Single Command Correctness Fix"
echo "============================================================"

cd cpp

# Clean previous builds
rm -f meteor_single_command_fixed

# Build with all optimizations (same flags as pipeline-correct server)
echo "⚙️  Building with full optimizations..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -pthread \
    -mavx512f -mavx512dq -mavx2 -mavx -msse4.2 -msse4.1 -mfma \
    -o meteor_single_command_fixed \
    meteor_phase1_2b_syscall_reduction_single_command_fixed.cpp \
    -lboost_fiber -lboost_context -lboost_system -luring

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    ls -la meteor_single_command_fixed
    
    echo ""
    echo "🚀 Ready to test:"
    echo "  ./meteor_single_command_fixed -c 4 -s 4   # 4C test"
    echo "  ./meteor_single_command_fixed -c 12 -s 12 # 12C test"
    echo ""
    echo "📊 Benchmark with:"
    echo "  ./test_single_command_correctness.sh"
else
    echo "❌ Build failed!"
    exit 1
fi












