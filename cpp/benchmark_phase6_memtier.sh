#!/bin/bash

echo "🚀 PHASE 6 STEP 1 - MEMTIER_BENCHMARK TEST"
echo "=========================================="
echo "Testing Phase 6 with memtier_benchmark instead of redis-benchmark"
echo "Previous results: Phase 6 showed ~395 RPS with redis-benchmark"
echo "Let's see if memtier_benchmark gives different results"
echo

cd ~/meteor

echo "🔧 Stopping any running servers..."
pkill -f meteor || true
sleep 3

echo
echo "==============================================="
echo "🚀 PHASE 6 STEP 1 - 4 CORE MEMTIER TEST"
echo "==============================================="
echo "Configuration: 4 cores, 8 shards, 256MB memory"
echo "Using same config that gave Phase 5: 165K RPS"
echo

echo "Starting Phase 6 Step 1 optimized (4-core)..."
nohup ./meteor_phase6_step1_optimized -h 127.0.0.1 -p 6379 -c 4 -s 8 -m 256 -l > /tmp/phase6_memtier.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting 15 seconds for server initialization..."
sleep 15

echo "🔍 Checking if server is running..."
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server is running"
    
    if ss -tlnp | grep :6379; then
        echo "✅ Server listening on port 6379"
        
        echo
        echo "📊 MEMTIER_BENCHMARK TEST 1: Basic Performance"
        echo "============================================="
        echo "Test: 10K requests, 2 threads, 5 connections each"
        memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 5000 --ratio=1:1 --pipeline=1
        
        echo
        echo "📊 MEMTIER_BENCHMARK TEST 2: With Pipeline"
        echo "=========================================="
        echo "Test: 10K requests, 2 threads, 5 connections, pipeline=10"
        memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 5000 --ratio=1:1 --pipeline=10
        
        echo
        echo "📊 MEMTIER_BENCHMARK TEST 3: Higher Load"
        echo "========================================"
        echo "Test: 20K requests, 4 threads, 10 connections each"
        memtier_benchmark -h 127.0.0.1 -p 6379 -t 4 -c 10 -n 5000 --ratio=1:1 --pipeline=1
        
    else
        echo "❌ Server not listening on port 6379"
        echo "Server log:"
        tail -20 /tmp/phase6_memtier.log
    fi
else
    echo "❌ Server process died"
    echo "Server log:"
    tail -20 /tmp/phase6_memtier.log
fi

echo
echo "🔧 Stopping Phase 6..."
pkill -f meteor || true
sleep 5

echo
echo "==============================================="
echo "🚀 PHASE 5 COMPARISON - 4 CORE MEMTIER TEST"
echo "==============================================="
echo "Running Phase 5 with same config for comparison"
echo

echo "Starting Phase 5 Step 4A (4-core)..."
nohup ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 4 -s 8 -m 256 -l > /tmp/phase5_memtier.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting 15 seconds for server initialization..."
sleep 15

echo "🔍 Checking if server is running..."
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server is running"
    
    if ss -tlnp | grep :6379; then
        echo "✅ Server listening on port 6379"
        
        echo
        echo "📊 PHASE 5 MEMTIER_BENCHMARK TEST"
        echo "================================"
        echo "Same test as Phase 6 for comparison"
        memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 5000 --ratio=1:1 --pipeline=1
        
    else
        echo "❌ Server not listening on port 6379"
        echo "Server log:"
        tail -20 /tmp/phase5_memtier.log
    fi
else
    echo "❌ Server process died"
    echo "Server log:"
    tail -20 /tmp/phase5_memtier.log
fi

echo
echo "📊 COMPREHENSIVE PERFORMANCE COMPARISON:"
echo "======================================="
echo "BASELINE (Previous Tests):"
echo "• Phase 5 + redis-benchmark:  165,289 RPS"
echo "• Phase 6 + redis-benchmark:      395 RPS (99.75% regression)"
echo
echo "CURRENT TEST (memtier_benchmark):"
echo "• Phase 5 + memtier_benchmark: [See Phase 5 results above]"
echo "• Phase 6 + memtier_benchmark: [See Phase 6 results above]"
echo
echo "🔍 ANALYSIS GOALS:"
echo "• If Phase 6 memtier >> Phase 6 redis: redis-benchmark compatibility issue"
echo "• If Phase 6 memtier ≈ Phase 6 redis: fundamental Phase 6 performance issue"
echo "• If Phase 6 memtier ≈ Phase 5 memtier: AVX-512/NUMA changes are neutral"

echo
echo "🔧 Final cleanup..."
pkill -f meteor || true
echo "✅ Memtier benchmark test completed"