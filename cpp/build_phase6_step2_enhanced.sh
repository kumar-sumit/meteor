#!/bin/bash

# **PHASE 6 STEP 2: Multi-Accept + CPU Affinity Build Script**
# Enhanced version with SO_REUSEPORT, mandatory CPU affinity, and all previous features

echo "🔨 Building Phase 6 Step 2: Multi-Accept + CPU Affinity Enhanced..."

# Compiler flags for maximum performance
CXXFLAGS="-std=c++17 -O3 -march=native -mtune=native -flto"
CXXFLAGS="$CXXFLAGS -DHAS_LINUX_EPOLL"
CXXFLAGS="$CXXFLAGS -mavx2 -mavx512f -mavx512vl -mavx512bw"
CXXFLAGS="$CXXFLAGS -pthread -Wall -Wextra"

# Linker flags
LDFLAGS="-pthread -lrt"

# Build command
g++ $CXXFLAGS sharded_server_phase6_step2_multiaccept_enhanced.cpp -o meteor_phase6_step2_enhanced $LDFLAGS

if [ $? -eq 0 ]; then
    echo "✅ Phase 6 Step 2 Enhanced build successful!"
    echo "📁 Binary: meteor_phase6_step2_enhanced"
    echo ""
    echo "🚀 Key Features:"
    echo "   ✅ SO_REUSEPORT Multi-Accept (eliminates single accept bottleneck)"
    echo "   ✅ Mandatory CPU Affinity (prevents thread migration)"
    echo "   ✅ Per-core dedicated accept threads"
    echo "   ✅ AVX-512 SIMD vectorization"
    echo "   ✅ Advanced performance monitoring"
    echo "   ✅ Lock-free data structures"
    echo "   ✅ SSD cache + hybrid cache"
    echo "   ✅ Connection migration"
    echo ""
    echo "🎯 Expected Performance: 10x+ improvement over Phase 6 Step 1"
    echo "📊 Target: Eliminate single accept thread bottleneck for linear scaling"
    ls -la meteor_phase6_step2_enhanced
else
    echo "❌ Build failed!"
    exit 1
fi