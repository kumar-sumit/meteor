#!/bin/bash

echo "🚀 Building PHASE 6 STEP 1: AVX-512 + Advanced Monitoring..."

# Compile with AVX-512 support
g++ -std=c++17 -O3 -march=native -mavx512f -mavx512vl -mavx512bw -mfma \
    -DHAS_LINUX_EPOLL -pthread \
    sharded_server_phase6_step1_avx512_numa.cpp \
    -o meteor_phase6_step1_avx512_numa

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📊 AVX-512 optimizations enabled"
    echo "🔍 Advanced bottleneck detection included"
    echo "🚀 Ready for deployment and testing"
else
    echo "❌ Build failed!"
    exit 1
fi