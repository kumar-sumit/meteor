#!/bin/bash

echo "=== Building Phase 7 Step 1 Fresh (io_uring integration) ==="

# Detect OS type
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Building for macOS (kqueue)..."
    clang++ -std=c++17 -O3 \
        -DHAS_MACOS_KQUEUE=1 \
        -I. \
        sharded_server_phase7_step1_fresh.cpp \
        -o meteor_phase7_fresh \
        -lpthread
else
    echo "Building for Linux (io_uring + epoll)..."
    
    # Check if liburing is available
    if pkg-config --exists liburing 2>/dev/null; then
        echo "liburing found, building with io_uring support..."
        g++ -std=c++17 -O3 -march=native -mavx2 -mavx512f \
            -DHAS_LINUX_EPOLL=1 \
            -DHAS_IO_URING=1 \
            -I. \
            sharded_server_phase7_step1_fresh.cpp \
            -o meteor_phase7_fresh \
            $(pkg-config --cflags --libs liburing) \
            -lpthread
    else
        echo "liburing not found, building with epoll only..."
        g++ -std=c++17 -O3 -march=native -mavx2 -mavx512f \
            -DHAS_LINUX_EPOLL=1 \
            -I. \
            sharded_server_phase7_step1_fresh.cpp \
            -o meteor_phase7_fresh \
            -lpthread
    fi
fi

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    ls -la meteor_phase7_fresh
else
    echo "❌ Build failed!"
    exit 1
fi