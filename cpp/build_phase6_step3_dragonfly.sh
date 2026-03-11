#!/bin/bash

SOURCE_FILE="sharded_server_phase6_step3_dragonfly_style.cpp"
BINARY_NAME="meteor_phase6_step3_dragonfly_style"

echo "🔨 Building Phase 6 Step 3: DragonflyDB-Style Pipeline Processing..."

g++ -std=c++17 -O3 -march=native -mtune=native -flto \
    -DHAS_LINUX_EPOLL \
    -mavx2 -mavx512f -mavx512vl -mavx512bw \
    -pthread -Wall -Wextra \
    ${SOURCE_FILE} -o ${BINARY_NAME} -lrt

if [ $? -eq 0 ]; then
    echo "✅ Build successful! Binary: ${BINARY_NAME}"
    ls -la ${BINARY_NAME}
else
    echo "❌ Build failed!"
    exit 1
fi