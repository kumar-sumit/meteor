#!/bin/bash

# **PHASE 5 STEP 4A Build Script: SIMD + Lock-Free + Advanced Monitoring**
# Build and test the enhanced server with vectorized operations and monitoring

set -e

echo "🔥 Building PHASE 5 STEP 4A: SIMD + Lock-Free + Advanced Monitoring"

# Move to the correct location
cd ~/meteor/cpp || { echo "❌ Failed to cd to ~/meteor/cpp"; exit 1; }

# Ensure the source file is present
if [ ! -f "sharded_server_phase5_step4a_simd_lockfree_monitoring.cpp" ]; then
    echo "❌ Source file not found!"
    exit 1
fi

echo "✅ Source file found"

# Build with optimizations for SIMD
echo "🔧 Compiling with SIMD optimizations..."
g++ -std=c++17 -O3 -march=native -mavx2 -mfma -DHAS_LINUX_EPOLL \
    -pthread -ljemalloc \
    sharded_server_phase5_step4a_simd_lockfree_monitoring.cpp \
    -o meteor_phase5_step4a_simd_lockfree_monitoring \
    2>&1 | tee build.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ Compilation failed! Check build.log for details"
    tail -20 build.log
    exit 1
fi

echo "✅ Compilation successful!"

# Kill any existing server instances
echo "🧹 Cleaning up existing server instances..."
pkill -f meteor_phase5 || true
sleep 2

# Start the server
echo "🚀 Starting PHASE 5 STEP 4A server..."
./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 4 -m 512 -l &
SERVER_PID=$!

# Give server time to start
sleep 3

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "❌ Server failed to start"
    exit 1
fi

echo "✅ Server started with PID $SERVER_PID"

# Wait a moment for full initialization
sleep 2

# Run benchmark
echo "📊 Running benchmark with memtier_benchmark..."
memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 \
    --key-pattern=R:R --key-minimum=1 --key-maximum=100000 \
    2>&1 | tee step4a_benchmark.log

# Extract key metrics
echo ""
echo "🎯 PHASE 5 STEP 4A BENCHMARK RESULTS:"
echo "======================================"

# Extract throughput and latency
grep "Totals" step4a_benchmark.log | tail -1 | while read line; do
    echo "📈 $line"
done

# Show SIMD and monitoring features
echo ""
echo "🔥 STEP 4A ADVANCED FEATURES:"
echo "⚡ SIMD Vectorization: AVX2 enabled"
echo "🔒 Lock-Free Structures: Contention-aware queues and hash maps"
echo "📊 Advanced Monitoring: Real-time metrics collection"
echo "🔄 Connection Migration: Optimized cross-core communication"

# Stop the server
echo ""
echo "🛑 Stopping server..."
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true

echo "✅ PHASE 5 STEP 4A test completed!"
echo "📋 Logs saved to: step4a_benchmark.log"