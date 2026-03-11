#!/bin/bash

# Build surgical TTL implementation using /dev/shm completely (including compiler temp files)
echo "🔧 SURGICAL TTL BUILD - Full /dev/shm with AVX-512 SIMD"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== SURGICAL TTL BUILD PROCESS ==="
echo "$(date): Starting build with full /dev/shm usage and AVX-512 SIMD"

# Clean up any previous builds
pkill -f meteor 2>/dev/null || true
rm -f meteor_surgical_test 2>/dev/null || true

# Copy source to RAM disk (/dev/shm) 
echo "📁 Copying source to /dev/shm..."
cp meteor_ttl_surgical.cpp /dev/shm/
cd /dev/shm

# Set TMPDIR to use /dev/shm for compiler temporary files
export TMPDIR=/dev/shm

echo "🏗️  Building with full AVX-512 SIMD optimizations (all files in RAM)..."

# Build with comprehensive optimizations matching meteor_final_correct
g++ -std=c++20 -O3 -DNDEBUG \
    -march=native \
    -mavx512f -mavx512dq -mavx512cd -mavx512bw -mavx512vl \
    -mavx2 -mavx -msse4.2 -msse4.1 -mssse3 -msse3 -msse2 -msse \
    -mpopcnt -mlzcnt -mbmi -mbmi2 \
    -DBOOST_FIBER_NO_EXCEPTIONS \
    -pthread \
    -funroll-loops \
    -ffast-math \
    -ftree-vectorize \
    -fomit-frame-pointer \
    -finline-functions \
    meteor_ttl_surgical.cpp -o meteor_surgical_test \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ BUILD SUCCESSFUL"
    
    # Copy binary back to main directory
    echo "📦 Copying binary back to main directory..."
    cp meteor_surgical_test /mnt/externalDisk/meteor/
    
    # Verify binary
    echo "🔍 Verifying binary..."
    ls -la /mnt/externalDisk/meteor/meteor_surgical_test
    file /mnt/externalDisk/meteor/meteor_surgical_test
    
    echo ""
    echo "🎉 SURGICAL TTL BUILD COMPLETED SUCCESSFULLY"
    echo "✅ Binary: /mnt/externalDisk/meteor/meteor_surgical_test"
    echo "✅ AVX-512 SIMD optimizations enabled"
    echo "✅ Ready for surgical testing"
    
else
    echo "❌ BUILD FAILED with exit code: $BUILD_STATUS"
    echo ""
    echo "=== Trying minimal build for surgical testing ==="
    
    # Ultra minimal build for surgical testing
    g++ -std=c++20 -O2 \
        -DBOOST_FIBER_NO_EXCEPTIONS \
        -pthread \
        meteor_ttl_surgical.cpp -o meteor_surgical_test \
        -lboost_fiber -lboost_context -lboost_system -luring 2>&1
        
    BUILD_STATUS=$?
    
    if [ $BUILD_STATUS -eq 0 ]; then
        echo "✅ MINIMAL BUILD SUCCESSFUL"
        cp meteor_surgical_test /mnt/externalDisk/meteor/
        echo "✅ Ready for surgical testing (minimal optimizations)"
    else
        echo "❌ EVEN MINIMAL BUILD FAILED"
        exit 1
    fi
fi

# Clean up /dev/shm
echo "🧹 Cleaning up /dev/shm..."
rm -f /dev/shm/meteor_ttl_surgical.cpp
rm -f /dev/shm/meteor_surgical_test
rm -f /dev/shm/cc* 2>/dev/null || true  # Clean up any compiler temp files

cd /mnt/externalDisk/meteor

EOF

echo "Build process completed."












