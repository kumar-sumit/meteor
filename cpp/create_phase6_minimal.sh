#!/bin/bash

# **Create Phase 6 Minimal - Remove Performance Killers**
# Strip out NUMA and AVX-512 to isolate regression causes

echo "🔧 Creating Phase 6 Minimal (Remove Performance Killers)"
echo "========================================================"

# Copy Phase 6 Step 1 as base
cp sharded_server_phase6_step1_avx512_numa.cpp sharded_server_phase6_minimal.cpp

echo "✅ Copied Phase 6 Step 1 as base"

# Remove NUMA optimizations (suspected cause #1)
echo "🔧 Removing NUMA optimizations..."
sed -i.bak '/#include <numa.h>/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/#include <numaif.h>/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/namespace numa/,/^}/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/numa_enabled_/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/numa_node_/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/numa::/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/NUMA/d' sharded_server_phase6_minimal.cpp

echo "✅ Removed NUMA optimizations"

# Replace AVX-512 with AVX2 (suspected cause #2)
echo "🔧 Replacing AVX-512 with AVX2..."
sed -i.bak 's/AVX-512/AVX2/g' sharded_server_phase6_minimal.cpp
sed -i.bak 's/avx512/avx2/g' sharded_server_phase6_minimal.cpp
sed -i.bak 's/__m512i/__m256i/g' sharded_server_phase6_minimal.cpp
sed -i.bak 's/_mm512_/_mm256_/g' sharded_server_phase6_minimal.cpp
sed -i.bak 's/8-way parallel/4-way parallel/g' sharded_server_phase6_minimal.cpp

echo "✅ Replaced AVX-512 with AVX2"

# Remove enhanced synchronization (suspected cause #3)
echo "🔧 Removing enhanced synchronization..."
sed -i.bak '/sleep_for.*milliseconds.*100/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/sleep_for.*seconds.*2/d' sharded_server_phase6_minimal.cpp
sed -i.bak '/Waiting for core threads to initialize/d' sharded_server_phase6_minimal.cpp

echo "✅ Removed enhanced synchronization delays"

# Update header comment
sed -i.bak '1,5c\
// **PHASE 6 MINIMAL: Regression Debug Version**\
// Removed: NUMA optimizations, AVX-512, enhanced sync\
// Goal: Restore Phase 5 performance levels\
// Building on Phase 5: SIMD + Lock-Free + Advanced Monitoring' sharded_server_phase6_minimal.cpp

echo "✅ Updated header comments"

# Create build script
cat > build_phase6_minimal.sh << 'EOF'
#!/bin/bash

echo "🔧 Building Phase 6 Minimal (Regression Debug)"
echo "=============================================="

# Use same compiler flags as Phase 5 (AVX2 instead of AVX-512)
g++ -std=c++17 -O3 -march=native -mavx2 -mfma -DHAS_LINUX_EPOLL \
    -pthread -Wall -Wextra -Wno-unused-parameter \
    sharded_server_phase6_minimal.cpp \
    -o meteor_phase6_minimal

if [ $? -eq 0 ]; then
    echo "✅ Phase 6 Minimal build successful!"
    echo "🎯 Expected: Should restore ~1.2M RPS performance"
    echo
    echo "Usage:"
    echo "./meteor_phase6_minimal -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l"
    echo
    echo "Benchmark:"
    echo "memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10"
else
    echo "❌ Phase 6 Minimal build failed!"
    exit 1
fi
EOF

chmod +x build_phase6_minimal.sh

echo
echo "✅ Phase 6 Minimal created successfully!"
echo
echo "📁 Files created:"
echo "  - sharded_server_phase6_minimal.cpp (source)"
echo "  - build_phase6_minimal.sh (build script)"
echo
echo "🎯 Changes made:"
echo "  ❌ Removed NUMA optimizations"
echo "  ❌ Replaced AVX-512 with AVX2" 
echo "  ❌ Removed enhanced synchronization delays"
echo "  ✅ Kept Phase 5 SIMD + Lock-Free architecture"
echo
echo "💡 Next steps:"
echo "1. Run: ./build_phase6_minimal.sh"
echo "2. Test with same config as Phase 5"
echo "3. Compare performance to isolate regression cause"