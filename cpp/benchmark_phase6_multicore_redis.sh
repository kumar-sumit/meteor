#!/bin/bash

echo "🚀 PHASE 6 STEP 1 OPTIMIZED - MULTI-CORE REDIS-BENCHMARK TEST"
echo "============================================================="
echo "Testing Phase 6 with NUMA node > 1 fix and reduced sync delays"
echo "Configurations: 12-core and 16-core"
echo "Baseline: Phase 5 (16-core) achieved only ~158K RPS (no scaling)"
echo "Expected: Phase 6 should break through the scaling barrier!"
echo

cd ~/meteor

echo "🔧 Stopping any running servers..."
pkill -f meteor || true
sleep 3

# Test 12-core configuration
echo
echo "==============================================="
echo "🚀 PHASE 6 STEP 1 - 12 CORE CONFIGURATION"
echo "==============================================="
echo "Configuration: 12 cores, 24 shards, 768MB memory"
echo

echo "Starting Phase 6 Step 1 optimized with 12-core config..."
nohup ./meteor_phase6_step1_optimized -h 127.0.0.1 -p 6379 -c 12 -s 24 -m 768 -l > /tmp/phase6_12core.log 2>&1 &
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
        echo "📊 RUNNING 12-CORE BENCHMARK..."
        echo "=============================="
        redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -d 100 -q
        
        echo
        echo "📈 12-CORE RESULTS ANALYSIS:"
        echo "• Phase 5 (4-core): 165K RPS"
        echo "• Phase 5 (16-core): 158K RPS (no scaling)"
        echo "• Phase 6 (12-core): [See results above]"
        echo
        
    else
        echo "❌ Server not listening on port 6379"
        tail -10 /tmp/phase6_12core.log
    fi
else
    echo "❌ Server process died"
    tail -10 /tmp/phase6_12core.log
fi

# Clean up and prepare for 16-core test
echo "🔧 Stopping 12-core server..."
pkill -f meteor || true
sleep 5

# Test 16-core configuration
echo
echo "==============================================="
echo "🚀 PHASE 6 STEP 1 - 16 CORE CONFIGURATION"
echo "==============================================="
echo "Configuration: 16 cores, 32 shards, 1024MB memory"
echo

echo "Starting Phase 6 Step 1 optimized with 16-core config..."
nohup ./meteor_phase6_step1_optimized -h 127.0.0.1 -p 6379 -c 16 -s 32 -m 1024 -l > /tmp/phase6_16core.log 2>&1 &
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
        echo "📊 RUNNING 16-CORE BENCHMARK..."
        echo "=============================="
        redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -d 100 -q
        
        echo
        echo "📈 COMPREHENSIVE PERFORMANCE COMPARISON:"
        echo "======================================="
        echo "• Phase 5 (4-core):  165,289 RPS"
        echo "• Phase 5 (16-core): 157,978 RPS (scaling failure)"
        echo "• Phase 6 (12-core): [See 12-core results above]"
        echo "• Phase 6 (16-core): [See 16-core results above]"
        echo
        echo "🎯 PHASE 6 IMPROVEMENTS:"
        echo "• AVX-512 SIMD (8-way vs 4-way parallel)"
        echo "• Smart NUMA (only enabled if nodes > 1)"
        echo "• Reduced sync delays (10ms vs 100ms)"
        echo "• Enhanced lock-free structures"
        echo
        
    else
        echo "❌ Server not listening on port 6379"
        tail -10 /tmp/phase6_16core.log
    fi
else
    echo "❌ Server process died"
    tail -10 /tmp/phase6_16core.log
fi

echo
echo "🔧 Final cleanup..."
pkill -f meteor || true
echo "✅ Multi-core benchmark completed"