#!/bin/bash

echo "=== BUILDING PHASE 7 STEP 1: DragonflyDB-Style Architecture ==="

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Building for macOS (no io_uring, using epoll fallback)"
    g++ -std=c++17 -O3 -march=native \
        -DHAS_LINUX_EPOLL=0 -DHAS_IO_URING=0 \
        -I. sharded_server_phase7_step1_dragonfly_architecture.cpp \
        -o meteor_phase7_dragonfly \
        -lpthread
else
    echo "🐧 Building for Linux with io_uring support"
    g++ -std=c++17 -O3 -march=native \
        -DHAS_LINUX_EPOLL=1 -DHAS_IO_URING=1 \
        -I. sharded_server_phase7_step1_dragonfly_architecture.cpp \
        -o meteor_phase7_dragonfly \
        $(pkg-config --libs liburing) -lpthread
fi

if [ $? -eq 0 ]; then
    echo "✅ Build successful: meteor_phase7_dragonfly"
    echo "🚀 Run with: ./meteor_phase7_dragonfly -p 6379 -c 4"
    echo "🎯 Expected: ~400K RPS (4 cores × 100K RPS per core)"
else
    echo "❌ Build failed"
    exit 1
fi