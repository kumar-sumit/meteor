#!/bin/bash

echo "🔍 DEBUGGING PHASE 6 STEP 1 PERFORMANCE ISSUES"
echo "=============================================="
echo "Phase 6 showing ~395 RPS vs Phase 5's 158K RPS"
echo "This suggests a critical performance regression"
echo

cd ~/meteor

echo "🔧 Stopping any running servers..."
pkill -f meteor || true
sleep 3

echo
echo "🧪 TEST 1: Phase 6 with minimal 4-core config"
echo "============================================="
echo "Configuration: 4 cores, 8 shards, 256MB memory"
echo

echo "Starting Phase 6 Step 1 optimized (4-core)..."
nohup ./meteor_phase6_step1_optimized -h 127.0.0.1 -p 6379 -c 4 -s 8 -m 256 -l > /tmp/phase6_debug.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting 10 seconds for initialization..."
sleep 10

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server is running"
    
    if ss -tlnp | grep :6379; then
        echo "✅ Server listening on port 6379"
        
        echo
        echo "📊 Testing with redis-benchmark (small test)..."
        echo "Requests: 10,000, Clients: 10"
        redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 10000 -c 10 -d 100 -q
        
        echo
        echo "📊 Testing with manual commands..."
        echo "SET test_key test_value" | nc 127.0.0.1 6379
        echo "GET test_key" | nc 127.0.0.1 6379
        
    else
        echo "❌ Server not listening"
        echo "Server log:"
        tail -20 /tmp/phase6_debug.log
    fi
else
    echo "❌ Server died"
    echo "Server log:"
    tail -20 /tmp/phase6_debug.log
fi

echo
echo "🔧 Stopping Phase 6..."
pkill -f meteor || true
sleep 3

echo
echo "🧪 TEST 2: Phase 5 comparison (4-core)"
echo "======================================"
echo "Running Phase 5 with same 4-core config for comparison"
echo

echo "Starting Phase 5 Step 4A (4-core)..."
nohup ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 4 -s 8 -m 256 -l > /tmp/phase5_debug.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting 10 seconds for initialization..."
sleep 10

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server is running"
    
    if ss -tlnp | grep :6379; then
        echo "✅ Server listening on port 6379"
        
        echo
        echo "📊 Testing Phase 5 with redis-benchmark (same test)..."
        redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 10000 -c 10 -d 100 -q
        
    else
        echo "❌ Server not listening"
        echo "Server log:"
        tail -20 /tmp/phase5_debug.log
    fi
else
    echo "❌ Server died"
    echo "Server log:"
    tail -20 /tmp/phase5_debug.log
fi

echo
echo "📊 PERFORMANCE COMPARISON SUMMARY:"
echo "================================="
echo "• Phase 5 (4-core): [See Phase 5 results above]"
echo "• Phase 6 (4-core): [See Phase 6 results above]"
echo
echo "🔍 ANALYSIS:"
echo "• If Phase 6 << Phase 5, then AVX-512/NUMA changes introduced regression"
echo "• If Phase 6 ≈ Phase 5, then multi-core scaling is the issue"
echo "• If both are low, then redis-benchmark compatibility issue"

echo
echo "🔧 Final cleanup..."
pkill -f meteor || true
echo "✅ Debug test completed"