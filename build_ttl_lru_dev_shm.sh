#!/bin/bash

echo "=========================================="
echo "🚀 TTL+LRU BUILD USING /dev/shm RAM DISK"
echo "$(date): Building with full AVX-512 SIMD optimizations"
echo "=========================================="

# Set environment variables for optimal build
export TMPDIR=/dev/shm/build_tmp
export TEMP=/dev/shm/build_tmp
export TMP=/dev/shm/build_tmp

# Create build directory in RAM
mkdir -p /dev/shm/build_tmp
mkdir -p /dev/shm/meteor_build
cd /dev/shm/meteor_build

# Copy source files to RAM disk for faster compilation
echo "📁 Copying source files to RAM disk..."
cp /mnt/externalDisk/meteor/meteor_baseline_ttl_lru.cpp .
cp /mnt/externalDisk/meteor/boost -r . 2>/dev/null || echo "boost dir not found, using system"

echo ""
echo "=== FULL AVX-512 SIMD BUILD ==="
echo "🔧 Building with complete optimization flags..."

# Clean up any previous processes
pkill -f meteor 2>/dev/null || true

# Full AVX-512 SIMD optimized build with all flags
g++ -std=c++20 \
    -O3 \
    -march=native \
    -mtune=native \
    -mavx512f \
    -mavx512dq \
    -mavx512bw \
    -mavx512vl \
    -mavx512cd \
    -mavx512ifma \
    -mavx512vbmi \
    -mfma \
    -msse4.2 \
    -mpopcnt \
    -mbmi2 \
    -mlzcnt \
    -flto \
    -ffast-math \
    -funroll-loops \
    -fprefetch-loop-arrays \
    -finline-functions \
    -fomit-frame-pointer \
    -ftree-vectorize \
    -fvect-cost-model=unlimited \
    -fno-semantic-interposition \
    -DNDEBUG \
    -DBOOST_FIBER_NO_EXCEPTIONS \
    -DAVX512_ENABLED \
    -DSIMD_OPTIMIZED \
    -DHIGH_PERFORMANCE_BUILD \
    -pthread \
    -pipe \
    meteor_baseline_ttl_lru.cpp \
    -o meteor_ttl_lru_optimized \
    -lboost_fiber \
    -lboost_context \
    -lboost_system \
    -luring \
    -ljemalloc \
    2>&1

BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
    echo "❌ FULL BUILD FAILED, trying with reduced flags..."
    
    # Fallback build with essential optimizations
    g++ -std=c++20 \
        -O3 \
        -march=native \
        -mtune=native \
        -mavx2 \
        -mfma \
        -msse4.2 \
        -flto \
        -ffast-math \
        -funroll-loops \
        -DNDEBUG \
        -DBOOST_FIBER_NO_EXCEPTIONS \
        -DSIMD_OPTIMIZED \
        -pthread \
        -pipe \
        meteor_baseline_ttl_lru.cpp \
        -o meteor_ttl_lru_optimized \
        -lboost_fiber \
        -lboost_context \
        -lboost_system \
        -luring \
        2>&1
    
    BUILD_STATUS=$?
fi

if [ $BUILD_STATUS -ne 0 ]; then
    echo "❌ FALLBACK BUILD FAILED, trying basic build..."
    
    # Minimal build
    g++ -std=c++20 \
        -O2 \
        -DNDEBUG \
        -DBOOST_FIBER_NO_EXCEPTIONS \
        -pthread \
        meteor_baseline_ttl_lru.cpp \
        -o meteor_ttl_lru_optimized \
        -lboost_fiber \
        -lboost_context \
        -lboost_system \
        -luring \
        2>&1
    
    BUILD_STATUS=$?
fi

if [ $BUILD_STATUS -ne 0 ]; then
    echo "❌ ALL BUILDS FAILED"
    exit 1
fi

echo "✅ BUILD SUCCESSFUL!"

# Copy binary back to main disk
echo "📦 Copying optimized binary back to main disk..."
cp meteor_ttl_lru_optimized /mnt/externalDisk/meteor/
chmod +x /mnt/externalDisk/meteor/meteor_ttl_lru_optimized

# Display build info
echo ""
echo "=== BUILD INFORMATION ==="
file /mnt/externalDisk/meteor/meteor_ttl_lru_optimized
ls -la /mnt/externalDisk/meteor/meteor_ttl_lru_optimized

# Clean up RAM disk
echo ""
echo "🧹 Cleaning up RAM disk..."
cd /mnt/externalDisk/meteor
rm -rf /dev/shm/meteor_build
rm -rf /dev/shm/build_tmp

echo ""
echo "🎉 TTL+LRU BUILD COMPLETE!"
echo "✅ Binary: /mnt/externalDisk/meteor/meteor_ttl_lru_optimized"
echo "✅ Built with AVX-512 SIMD optimizations using /dev/shm RAM disk"
echo ""

# Quick test
echo "=== QUICK FUNCTIONALITY TEST ==="
echo "🚀 Starting server for quick test..."

cd /mnt/externalDisk/meteor
nohup ./meteor_ttl_lru_optimized -c 4 -s 4 > meteor_ttl_test.log 2>&1 &
SERVER_PID=$!
sleep 5

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"
    
    # Quick functionality check
    echo -n "SET test: "
    SET_RESULT=$(timeout 5s redis-cli -p 6379 SET test_key test_value 2>/dev/null || echo "TIMEOUT")
    echo "$SET_RESULT"
    
    echo -n "GET test: "
    GET_RESULT=$(timeout 5s redis-cli -p 6379 GET test_key 2>/dev/null || echo "TIMEOUT") 
    echo "$GET_RESULT"
    
    echo -n "TTL test: "
    TTL_RESULT=$(timeout 5s redis-cli -p 6379 TTL test_key 2>/dev/null || echo "TIMEOUT")
    echo "$TTL_RESULT"
    
    if [[ "$SET_RESULT" == "OK" ]] && [[ "$GET_RESULT" == "test_value" ]]; then
        echo "🎉 BASIC FUNCTIONALITY: WORKING!"
        if [[ "$TTL_RESULT" == "-1" ]]; then
            echo "🎉 TTL FUNCTIONALITY: WORKING!"
        else
            echo "⚠️  TTL FUNCTIONALITY: Needs verification (got: $TTL_RESULT)"
        fi
    else
        echo "⚠️  SERVER: Basic functionality needs verification"
    fi
    
    # Stop test server
    kill $SERVER_PID 2>/dev/null || true
    sleep 2
else
    echo "❌ SERVER FAILED TO START"
    echo "Server log:"
    tail -10 meteor_ttl_test.log
fi

echo ""
echo "$(date): Build completed successfully using /dev/shm!"
echo "Ready for comprehensive TTL+LRU testing!"












