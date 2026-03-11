#!/bin/bash

# Build TTL-enhanced baseline using /dev/shm with full optimizations
echo "🔧 BUILDING TTL-ENHANCED BASELINE"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== TTL BASELINE BUILD PROCESS ==="
echo "$(date): Building TTL-enhanced baseline with DragonflyDB principles"

# Copy source to RAM disk
cp meteor_working_baseline_for_ttl.cpp /dev/shm/
cd /dev/shm

# Set TMPDIR for compiler temp files
export TMPDIR=/dev/shm

echo "🏗️  Building TTL baseline with full optimizations..."
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
    meteor_working_baseline_for_ttl.cpp -o meteor_ttl_baseline \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ TTL BASELINE BUILD SUCCESSFUL"
    cp meteor_ttl_baseline /mnt/externalDisk/meteor/
    ls -la /mnt/externalDisk/meteor/meteor_ttl_baseline
    file /mnt/externalDisk/meteor/meteor_ttl_baseline
    echo "🎉 TTL BASELINE READY FOR TESTING"
else
    echo "❌ TTL BASELINE BUILD FAILED"
    exit 1
fi

# Clean up
rm -f /dev/shm/meteor_working_baseline_for_ttl.cpp
rm -f /dev/shm/meteor_ttl_baseline
cd /mnt/externalDisk/meteor

EOF












