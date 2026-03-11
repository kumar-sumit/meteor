#!/bin/bash

echo "🐲 DRAGONFLY BENCHMARK ON SSD-TIERING VM"
echo "========================================"
echo "VM: $(hostname) - $(nproc) cores, $(free -h | grep Mem | awk '{print $2}') RAM"
echo "Date: $(date)"
echo "Comparison target: Phase 5 Step 4A (160K RPS redis-benchmark, 39K RPS memtier)"
echo

# Create results directory
RESULTS_DIR="~/dragonfly_benchmark_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"
echo "📁 Results directory: $RESULTS_DIR"

# Stop any running servers
echo "🛑 Stopping any existing servers..."
pkill -f meteor || true
pkill -f dragonfly || true
sleep 5

# Check DragonflyDB installation
echo "🔍 Checking DragonflyDB installation..."
if command -v dragonfly &> /dev/null; then
    echo "✅ DragonflyDB found"
    dragonfly --version | tee "$RESULTS_DIR/dragonfly_version.txt"
else
    echo "❌ DragonflyDB not found"
    exit 1
fi

echo
echo "🚀 STARTING DRAGONFLY WITH OPTIMAL CONFIGURATION"
echo "==============================================="
echo "Configuration: 16 threads, port 6380, optimized for 16-core VM"
echo "Command: dragonfly --port=6380 --proactor_threads=16 --logtostderr"

nohup dragonfly --port=6380 --proactor_threads=16 --logtostderr > "$RESULTS_DIR/dragonfly.log" 2>&1 &
DRAGONFLY_PID=$!
echo "DragonflyDB started with PID: $DRAGONFLY_PID"

echo "Waiting 20 seconds for DragonflyDB initialization..."
sleep 20

# Verify DragonflyDB is running
echo "🔍 Verifying DragonflyDB status..."
if ps -p $DRAGONFLY_PID > /dev/null; then
    echo "✅ DragonflyDB process running"
    if ss -tlnp | grep :6380; then
        echo "✅ DragonflyDB listening on port 6380"
        echo
        echo "📊 System status after startup:"
        uptime | tee "$RESULTS_DIR/system_status.txt"
        free -h | grep Mem | tee -a "$RESULTS_DIR/system_status.txt"
        echo
        echo "🔥 DragonflyDB ready for benchmarking!"
    else
        echo "❌ DragonflyDB not listening on port 6380"
        echo "Log (last 20 lines):"
        tail -20 "$RESULTS_DIR/dragonfly.log"
        exit 1
    fi
else
    echo "❌ DragonflyDB process died"
    echo "Log (last 20 lines):"
    tail -20 "$RESULTS_DIR/dragonfly.log"
    exit 1
fi

echo
echo "📊 BENCHMARK 1: REDIS-BENCHMARK - STANDARD LOAD"
echo "==============================================="
echo "Test: SET/GET, 100K requests, 50 clients, 100 bytes"
echo "Phase 5 baseline: 160,514 SET / 165,017 GET RPS"
echo

redis-benchmark -h 127.0.0.1 -p 6380 -t set,get -n 100000 -c 50 -d 100 -q | tee "$RESULTS_DIR/redis_bench_test1.txt"

echo
echo "📊 BENCHMARK 2: REDIS-BENCHMARK - HIGHER LOAD"
echo "============================================="
echo "Test: SET/GET, 200K requests, 100 clients, 100 bytes"
echo "Phase 5 baseline: 146,628 SET / 169,062 GET RPS"
echo

redis-benchmark -h 127.0.0.1 -p 6380 -t set,get -n 200000 -c 100 -d 100 -q | tee "$RESULTS_DIR/redis_bench_test2.txt"

echo
echo "📊 BENCHMARK 3: REDIS-BENCHMARK - MAXIMUM LOAD"
echo "==============================================="
echo "Test: SET/GET, 300K requests, 150 clients, 100 bytes"
echo "Phase 5 baseline: 160,428 SET / 162,602 GET RPS"
echo

redis-benchmark -h 127.0.0.1 -p 6380 -t set,get -n 300000 -c 150 -d 100 -q | tee "$RESULTS_DIR/redis_bench_test3.txt"

echo
echo "📊 BENCHMARK 4: MEMTIER_BENCHMARK - SUSTAINED LOAD"
echo "=================================================="
echo "Test: 50 connections, 30 seconds, 1:1 ratio"
echo "Phase 5 baseline: 39,323 RPS"
echo

memtier_benchmark -h 127.0.0.1 -p 6380 --ratio=1:1 -c 50 --test-time=30 --distinct-client-seed --randomize | tee "$RESULTS_DIR/memtier_test.txt"

echo
echo "📊 BENCHMARK 5: HIGH THROUGHPUT STRESS TEST"
echo "==========================================="
echo "Test: Pushing DragonflyDB to its limits"
echo "Expected: Multi-core scaling advantage"
echo

redis-benchmark -h 127.0.0.1 -p 6380 -t set,get -n 500000 -c 200 -d 100 --threads 8 -q | tee "$RESULTS_DIR/redis_bench_stress.txt"

echo
echo "📈 PERFORMANCE ANALYSIS"
echo "======================"

echo "🔥 DRAGONFLY RESULTS SUMMARY:"
echo "============================="
echo
echo "Redis-benchmark Test 1 (50 clients):"
grep -E "(SET|GET):" "$RESULTS_DIR/redis_bench_test1.txt" | head -2

echo
echo "Redis-benchmark Test 2 (100 clients):"
grep -E "(SET|GET):" "$RESULTS_DIR/redis_bench_test2.txt" | head -2

echo
echo "Redis-benchmark Test 3 (150 clients):"
grep -E "(SET|GET):" "$RESULTS_DIR/redis_bench_test3.txt" | head -2

echo
echo "Redis-benchmark Stress Test (200 clients, 8 threads):"
grep -E "(SET|GET):" "$RESULTS_DIR/redis_bench_stress.txt" | head -2

echo
echo "Memtier-benchmark (30-second sustained):"
grep -E "Totals.*ops/sec" "$RESULTS_DIR/memtier_test.txt" | head -1

echo
echo "📊 COMPARISON WITH PHASE 5 STEP 4A:"
echo "==================================="
echo "PHASE 5 STEP 4A (16-core baseline):"
echo "• Redis-benchmark (50 clients):  160,514 SET / 165,017 GET RPS"
echo "• Redis-benchmark (100 clients): 146,628 SET / 169,062 GET RPS"
echo "• Redis-benchmark (150 clients): 160,428 SET / 162,602 GET RPS"
echo "• Memtier-benchmark:             39,323 RPS"
echo
echo "DRAGONFLY (16-core results): [See above]"
echo
echo "PERFORMANCE IMPROVEMENT FACTOR:"
echo "• Expected: 2-25x based on DragonflyDB claims"
echo "• Target: Break through Phase 5's 160K RPS ceiling"
echo "• Multi-core scaling: Should utilize all 16 cores effectively"

echo
echo "📁 DETAILED RESULTS SAVED TO: $RESULTS_DIR"
echo "============================================"
echo "Files created:"
ls -la "$RESULTS_DIR/"

echo
echo "🔧 Cleaning up..."
pkill -f dragonfly || true
sleep 2

echo
echo "✅ DragonflyDB benchmark completed!"
echo "Results saved to: $RESULTS_DIR"
echo
echo "🎯 KEY INSIGHTS:"
echo "• DragonflyDB architecture: Multi-threaded shared-nothing"
echo "• Phase 5 limitation: Single-thread bottleneck after 8 cores"
echo "• Expected advantage: True 16-core utilization"
echo "• Success criteria: >320K RPS to show 2x improvement"