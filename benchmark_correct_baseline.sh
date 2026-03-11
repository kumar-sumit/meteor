#!/bin/bash

# **CORRECT BASELINE PERFORMANCE BENCHMARK**
# Using EXACT parameters from docs/BENCHMARK_RESULTS.md that achieved 4.57M RPS
# Server: ./meteor_phase8_step23_io_uring_fixed -h 127.0.0.1 -p 6380 -c 16
# Memtier: memtier_benchmark -s 127.0.0.1 -p 6380 -c 32 -t 8 --test-time=10 --ratio=1:1 --pipeline=10

set -e

echo "🎯 **CORRECT BASELINE PERFORMANCE BENCHMARK**"
echo "File: sharded_server_phase8_step23_io_uring_fixed.cpp"
echo "Target: Reproduce documented 4.57M RPS baseline performance"
echo "Critical: This is our TRUE reference point for temporal coherence"
echo ""

cd /dev/shm

# Kill any existing servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🔧 Building correct baseline server..."
g++ -std=c++17 -O3 -march=native -mtune=native \
    -ffast-math -funroll-loops -fprefetch-loop-arrays -ftree-vectorize \
    -fno-semantic-interposition -flto -fwhole-program \
    -mavx2 -mavx512f -mavx512cd -mavx512bw -mavx512dq -mavx512vl -mfma \
    -pthread -fopenmp -DHAS_LINUX_EPOLL=1 \
    -DNDEBUG -D_GNU_SOURCE -falign-functions=32 -falign-loops=32 -mcx16 \
    -Wall -Wextra -Wno-unused-parameter -Wno-unused-variable -Wno-sign-compare \
    sharded_server_phase8_step23_io_uring_fixed.cpp \
    -o meteor_correct_baseline \
    -luring -latomic -lnuma -static-libgcc -static-libstdc++

if [ $? -ne 0 ]; then
    echo "❌ Correct baseline build failed!"
    exit 1
fi

echo "✅ Correct baseline build successful"
echo ""

echo "🚀 Starting correct baseline server (16 cores)..."
./meteor_correct_baseline -h 127.0.0.1 -p 6380 -c 16 > correct_baseline_server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to initialize
sleep 8

echo "📡 Testing server connectivity..."
if ! redis-cli -p 6380 ping > /dev/null 2>&1; then
    echo "❌ Server not responding! Check logs:"
    tail -10 correct_baseline_server.log
    kill $SERVER_PID 2>/dev/null || true
    exit 1
fi

echo "✅ Correct baseline server responding to PING"
echo ""

# Test 1: EXACT HIGH-PERFORMANCE COMMAND (documented 4.57M RPS)
echo "=== CORRECT BASELINE TEST: HIGH-PERFORMANCE COMMAND ==="
echo "Using EXACT parameters from benchmark results documentation"
echo "Expected: ~4.57M RPS (documented performance)"

echo "Running memtier_benchmark with HIGH-PERFORMANCE parameters..."
echo "Command: memtier_benchmark -s 127.0.0.1 -p 6380 -c 32 -t 8 --test-time=10 --ratio=1:1 --pipeline=10"
echo ""

timeout 20 memtier_benchmark \
    -s 127.0.0.1 -p 6380 \
    -c 32 -t 8 \
    --test-time=10 \
    --ratio=1:1 \
    --pipeline=10 \
    --data-size=100 \
    --key-pattern=R:R \
    --print-percentiles=50,95,99 > correct_baseline_results.txt 2>&1

echo "🎯 **CORRECT BASELINE PERFORMANCE RESULTS:**"
echo ""
grep -E "Totals.*ops/sec" correct_baseline_results.txt | tail -1
echo ""

# Test 2: Alternative configurations for comparison
echo "=== ADDITIONAL BASELINE TESTS ==="

# Test 2a: 12 cores configuration (documented 4.37M RPS)
echo "📊 **Test 2a: 12 cores configuration**"
kill $SERVER_PID 2>/dev/null || true
sleep 3

echo "Starting 12-core server..."
./meteor_correct_baseline -h 127.0.0.1 -p 6380 -c 12 > baseline_12core_server.log 2>&1 &
SERVER_PID=$!
sleep 5

timeout 20 memtier_benchmark \
    -s 127.0.0.1 -p 6380 \
    -c 30 -t 6 \
    --test-time=10 \
    --ratio=1:1 \
    --pipeline=10 \
    --data-size=100 \
    --key-pattern=R:R \
    --print-percentiles=50,95,99 > baseline_12core_results.txt 2>&1

echo "🎯 **12-Core Results:**"
grep -E "Totals.*ops/sec" baseline_12core_results.txt | tail -1
echo ""

# Test 2b: 4 cores configuration (documented 3.38M RPS)
echo "📊 **Test 2b: 4 cores configuration**"
kill $SERVER_PID 2>/dev/null || true
sleep 3

echo "Starting 4-core server..."
./meteor_correct_baseline -h 127.0.0.1 -p 6380 -c 4 > baseline_4core_server.log 2>&1 &
SERVER_PID=$!
sleep 5

timeout 20 memtier_benchmark \
    -s 127.0.0.1 -p 6380 \
    -c 20 -t 4 \
    --test-time=10 \
    --ratio=1:1 \
    --pipeline=10 \
    --data-size=100 \
    --key-pattern=R:R \
    --print-percentiles=50,95,99 > baseline_4core_results.txt 2>&1

echo "🎯 **4-Core Results:**"
grep -E "Totals.*ops/sec" baseline_4core_results.txt | tail -1
echo ""

echo "=== FINAL CORRECT BASELINE SUMMARY ==="
echo ""
echo "📊 **DOCUMENTED vs ACTUAL PERFORMANCE:**"

BASELINE_16C=$(grep "Totals" correct_baseline_results.txt | tail -1 | awk '{print $2}' | sed 's/,//g')
BASELINE_12C=$(grep "Totals" baseline_12core_results.txt | tail -1 | awk '{print $2}' | sed 's/,//g')
BASELINE_4C=$(grep "Totals" baseline_4core_results.txt | tail -1 | awk '{print $2}' | sed 's/,//g')

echo "   🎯 16 cores: $BASELINE_16C QPS (documented: 4.57M QPS)"
echo "   🎯 12 cores: $BASELINE_12C QPS (documented: 4.37M QPS)" 
echo "   🎯  4 cores: $BASELINE_4C QPS (documented: 3.38M QPS)"
echo ""

echo "🚨 **TEMPORAL COHERENCE REQUIREMENTS:**"
echo "   ✅ Use PIPELINE=10 for all temporal coherence benchmarks"
echo "   ✅ Use high-concurrency parameters (-c 32 -t 8 for 16 cores)"
echo "   ✅ Temporal implementations must achieve >= 90% of these numbers"
echo "   ✅ Single commands must have ZERO performance regression"
echo ""

echo "📝 **CORRECT BASELINE ESTABLISHED - READY FOR TEMPORAL COHERENCE**"

# Cleanup
kill $SERVER_PID 2>/dev/null || true
echo "Baseline server stopped (PID: $SERVER_PID)"
echo ""
echo "🚀 Use these EXACT parameters for all temporal coherence benchmarks!"















