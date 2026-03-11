#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🚀 METEOR AVX-512 SIMD OPTIMIZED BUILD"
echo "$(date): Building with complete performance optimizations"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== BUILD CONFIGURATION ==="
echo "🎯 Target: High-performance Redis-compatible server"
echo "🔧 Optimizations: AVX-512, SIMD, LTO, Native CPU tuning"
echo "📦 Libraries: Boost Fiber, io_uring, jemalloc"
echo ""

# Setup build environment
export TMPDIR=/mnt/externalDisk/meteor/tmp_build
mkdir -p $TMPDIR

echo "=== COMPILER FLAGS ==="
echo "Base optimization: -O3 -march=native -mtune=native"
echo "AVX-512 SIMD: -mavx512f -mavx512dq -mavx512bw -mavx512vl -mavx512cd"
echo "Additional SIMD: -mfma -msse4.2 -mpopcnt -mbmi2 -mlzcnt"
echo "Performance: -flto -ffast-math -funroll-loops -fprefetch-loop-arrays"
echo "Inlining: -finline-functions -fomit-frame-pointer"
echo "Release: -DNDEBUG -DBOOST_FIBER_NO_EXCEPTIONS"
echo "Features: -DAVX512_ENABLED -DSIMD_OPTIMIZED"
echo ""

echo "=== BUILDING METEOR WITH FULL OPTIMIZATIONS ==="
echo "Source: meteor_phase1_2b_syscall_reduction_single_command_fixed.cpp"
echo "Target: meteor_avx512_optimized"
echo ""

# Complete optimized build command
g++ -std=c++20 \
    -O3 \
    -march=native \
    -mtune=native \
    -mavx512f \
    -mavx512dq \
    -mavx512bw \
    -mavx512vl \
    -mavx512cd \
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
    -DNDEBUG \
    -DBOOST_FIBER_NO_EXCEPTIONS \
    -DAVX512_ENABLED \
    -DSIMD_OPTIMIZED \
    -pthread \
    -pipe \
    meteor_phase1_2b_syscall_reduction_single_command_fixed.cpp \
    -o meteor_avx512_optimized \
    -lboost_fiber \
    -lboost_context \
    -lboost_system \
    -luring \
    -ljemalloc \
    2>&1

BUILD_STATUS=$?

echo ""
echo "=== BUILD RESULTS ==="
if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ BUILD SUCCESSFUL: meteor_avx512_optimized created"
    echo ""
    
    # Display binary info
    echo "=== BINARY INFORMATION ==="
    ls -lh meteor_avx512_optimized
    echo ""
    
    echo "File type and architecture:"
    file meteor_avx512_optimized
    echo ""
    
    echo "=== STARTING OPTIMIZED SERVER ==="
    echo "Starting meteor_avx512_optimized with 4 cores, 4 shards..."
    nohup ./meteor_avx512_optimized -c 4 -s 4 > meteor_avx512.log 2>&1 &
    SERVER_PID=$!
    sleep 6
    
    # Check if server started
    if ps -p $SERVER_PID > /dev/null; then
        echo "✅ SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"
        echo ""
        
        echo "=== TESTING WITH REDIS-CLI ==="
        echo "Testing basic operations..."
        
        echo -n "SET test1 value1: "
        SET_RESULT=$(redis-cli -p 6379 SET test1 value1 2>/dev/null || echo "FAILED")
        echo "$SET_RESULT"
        
        echo -n "GET test1: "
        GET_RESULT=$(redis-cli -p 6379 GET test1 2>/dev/null || echo "FAILED")
        echo "$GET_RESULT"
        
        echo -n "PING: "
        PING_RESULT=$(redis-cli -p 6379 PING 2>/dev/null || echo "FAILED")
        echo "$PING_RESULT"
        
        echo ""
        if [[ "$SET_RESULT" == "OK" ]] && [[ "$GET_RESULT" == "value1" ]]; then
            echo "🎉 AVX-512 OPTIMIZED SERVER: WORKING PERFECTLY! 🎉"
            echo ""
            echo "✅ Ready for:"
            echo "   • TTL implementation"  
            echo "   • memtier benchmarking"
            echo "   • High-performance testing"
            echo ""
            echo "🚀 Performance optimizations active:"
            echo "   • AVX-512 SIMD instructions"
            echo "   • Native CPU tuning" 
            echo "   • Link-time optimization (LTO)"
            echo "   • Fast math and loop unrolling"
            echo "   • jemalloc memory allocator"
        else
            echo "⚠️  SERVER RUNNING BUT BASIC TESTS FAILED"
            echo "   SET result: '$SET_RESULT'"
            echo "   GET result: '$GET_RESULT'"
            echo "   PING result: '$PING_RESULT'"
        fi
        
        echo ""
        echo "Server is running. To stop: kill $SERVER_PID"
        
    else
        echo "❌ SERVER FAILED TO START"
        echo ""
        echo "Server log:"
        cat meteor_avx512.log
    fi
    
else
    echo "❌ BUILD FAILED"
    echo ""
    echo "Common issues and solutions:"
    echo "• Missing AVX-512: Use -march=skylake-avx512 instead of -march=native"
    echo "• Missing libraries: Install boost-devel, liburing-devel, jemalloc-devel"
    echo "• Linker errors: Check library paths and versions"
    echo ""
    echo "Fallback build (without AVX-512):"
    echo "g++ -std=c++20 -O3 -march=native -DNDEBUG -pthread meteor_phase1_2b_syscall_reduction_single_command_fixed.cpp -o meteor_optimized -lboost_fiber -lboost_context -lboost_system -luring"
fi

echo ""
echo "$(date): AVX-512 optimized build complete!"
echo "=========================================="












