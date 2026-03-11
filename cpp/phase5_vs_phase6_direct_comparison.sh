#!/bin/bash

# **DIRECT Phase 5 vs Phase 6 Step 1 Comparison**
# Using the EXACT configuration that claimed 1.2M RPS for Phase 5

echo "🔥 DIRECT Phase 5 vs Phase 6 Comparison"
echo "========================================"
echo "Using IDENTICAL configuration that claimed 1.2M RPS"
echo "Config: memtier_benchmark -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10"
echo "Server config: 4 cores, 16 shards, 512MB memory"
echo

# Kill any existing servers
pkill -f meteor 2>/dev/null || true
sleep 3

RESULTS_FILE="phase5_vs_phase6_direct_comparison.txt"
echo "Phase 5 vs Phase 6 Direct Comparison - $(date)" > $RESULTS_FILE
echo "Using EXACT configuration from Phase 5 claims" >> $RESULTS_FILE
echo "memtier_benchmark -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10" >> $RESULTS_FILE
echo >> $RESULTS_FILE

echo "📊 Test 1: Phase 5 Step 4A (claimed 1.2M RPS)"
echo "=============================================="
echo "Phase 5 Step 4A Results:" >> $RESULTS_FILE
echo "========================" >> $RESULTS_FILE

# Start Phase 5 server
./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6380 -c 4 -s 16 -m 512 -l > phase5_test.log 2>&1 &
PHASE5_PID=$!

sleep 5

if ps -p $PHASE5_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6380 > /dev/null; then
    echo "✅ Phase 5 server started and listening"
    
    echo "🔥 Running Phase 5 benchmark with EXACT original config..."
    if timeout 60 memtier_benchmark -h 127.0.0.1 -p 6380 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 2>&1 | tee -a $RESULTS_FILE; then
        echo "✅ Phase 5 benchmark completed"
    else
        echo "❌ Phase 5 benchmark failed or timed out"
        echo "Phase 5 benchmark failed" >> $RESULTS_FILE
    fi
    
    echo >> $RESULTS_FILE
    echo "Phase 5 server startup log:" >> $RESULTS_FILE
    head -15 phase5_test.log >> $RESULTS_FILE
    echo >> $RESULTS_FILE
else
    echo "❌ Phase 5 server failed to start"
    echo "Phase 5 server startup failed" >> $RESULTS_FILE
    echo "Error log:" >> $RESULTS_FILE
    cat phase5_test.log >> $RESULTS_FILE
fi

# Stop Phase 5
kill $PHASE5_PID 2>/dev/null || true
sleep 3

echo
echo "📊 Test 2: Phase 6 Step 1 (current version)"
echo "==========================================="
echo "Phase 6 Step 1 Results:" >> $RESULTS_FILE
echo "========================" >> $RESULTS_FILE

# Start Phase 6 server  
./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6381 -c 4 -s 16 -m 512 -l > phase6_test.log 2>&1 &
PHASE6_PID=$!

sleep 5

if ps -p $PHASE6_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6381 > /dev/null; then
    echo "✅ Phase 6 server started and listening"
    
    echo "🔥 Running Phase 6 benchmark with IDENTICAL config..."
    if timeout 60 memtier_benchmark -h 127.0.0.1 -p 6381 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 2>&1 | tee -a $RESULTS_FILE; then
        echo "✅ Phase 6 benchmark completed"
    else
        echo "❌ Phase 6 benchmark failed or timed out"
        echo "Phase 6 benchmark failed" >> $RESULTS_FILE
    fi
    
    echo >> $RESULTS_FILE
    echo "Phase 6 server startup log:" >> $RESULTS_FILE
    head -15 phase6_test.log >> $RESULTS_FILE
    echo >> $RESULTS_FILE
else
    echo "❌ Phase 6 server failed to start"
    echo "Phase 6 server startup failed" >> $RESULTS_FILE
    echo "Error log:" >> $RESULTS_FILE
    cat phase6_test.log >> $RESULTS_FILE
fi

# Stop Phase 6
kill $PHASE6_PID 2>/dev/null || true

echo
echo "🎯 COMPARISON SUMMARY"
echo "==================="
echo "Both tests used IDENTICAL configuration:"
echo "- Threads: 2, Connections: 5, Requests: 10,000, Pipeline: 10"
echo "- Server: 4 cores, 16 shards, 512MB memory"
echo
echo "📊 Results saved to: $RESULTS_FILE"
echo
echo "🔍 Quick Results Analysis:"
echo "=========================="
grep -E "(Totals|RPS|ops/sec)" $RESULTS_FILE 2>/dev/null || echo "Check $RESULTS_FILE for detailed results"

echo
echo "💡 Key Questions Answered:"
echo "1. Was Phase 5's 1.2M RPS claim accurate?"
echo "2. Did Phase 6 Step 1 improve or regress performance?"
echo "3. What is the actual performance baseline?"