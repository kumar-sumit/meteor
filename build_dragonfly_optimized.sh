#!/bin/bash

echo "🔨 Building METEOR DragonflyDB Optimized (Linear Scaling Version)..."
echo "🎯 Target: 8M+ ops/sec with per-command routing and optimal shard count"

# Build with Boost.Fibers support
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL \
    -march=native -mavx512f -mavx2 \
    -I/usr/include/boost \
    -pthread \
    -o meteor_dragonfly_optimized \
    cpp/meteor_dragonfly_optimized.cpp \
    -luring -lboost_fiber -lboost_context -lboost_system

if [ $? -eq 0 ]; then
    echo "✅ Build successful! Ready for 8M+ ops/sec benchmarks"
    echo ""
    echo "🚀 USAGE (DragonflyDB-Optimized Architecture):"
    echo "  12C:6S:  ./meteor_dragonfly_optimized -c 12 -s 6 -m 49152"  
    echo "  16C:8S:  ./meteor_dragonfly_optimized -c 16 -s 8 -m 49152"
    echo "  4C:4S:   ./meteor_dragonfly_optimized -c 4 -s 4 -m 49152"
    echo ""
    echo "🏗️ ARCHITECTURAL IMPROVEMENTS:"
    echo "  ✅ Per-command routing (not all-or-nothing pipeline)"
    echo "  ✅ Optimal shard count (6-8 shards, not 1:1 core:shard)"
    echo "  ✅ Boost.Fibers cooperative scheduling"
    echo "  ✅ Cross-shard message batching"
    echo "  ✅ Local fast path optimization"
    echo ""
else
    echo "❌ Build failed"
    exit 1
fi
