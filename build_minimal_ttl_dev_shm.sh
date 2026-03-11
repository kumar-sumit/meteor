#!/bin/bash

# Build minimal working TTL using /dev/shm
echo "🔧 MINIMAL TTL BUILD"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== MINIMAL TTL BUILD PROCESS ==="
echo "$(date): Building minimal TTL with /dev/shm"

# Copy source to RAM disk
cp meteor_minimal_working_ttl.cpp /dev/shm/
cd /dev/shm

# Set TMPDIR for compiler temp files
export TMPDIR=/dev/shm

echo "🏗️  Building minimal TTL..."
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
    meteor_minimal_working_ttl.cpp -o meteor_minimal_ttl \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ BUILD SUCCESSFUL"
    cp meteor_minimal_ttl /mnt/externalDisk/meteor/
    ls -la /mnt/externalDisk/meteor/meteor_minimal_ttl
    file /mnt/externalDisk/meteor/meteor_minimal_ttl
    echo "🎉 MINIMAL TTL READY FOR TESTING"
else
    echo "❌ BUILD FAILED"
    exit 1
fi

# Clean up
rm -f /dev/shm/meteor_minimal_working_ttl.cpp
rm -f /dev/shm/meteor_minimal_ttl
cd /mnt/externalDisk/meteor

EOF












