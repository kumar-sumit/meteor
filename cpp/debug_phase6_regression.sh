#!/bin/bash

# **Phase 6 Regression Debug Script**
# Systematically test what's causing the 31x performance regression

echo "🚨 Phase 6 Regression Debug Analysis"
echo "===================================="
echo "Phase 5 Step 4A: 1,197,920 ops/sec"
echo "Phase 6 Step 1: ~38,000 ops/sec" 
echo "Regression: 96.8% performance loss"
echo

# Kill any existing servers
pkill -f meteor 2>/dev/null || true
sleep 3

RESULTS_FILE="regression_debug_results.txt"
echo "Phase 6 Regression Debug Results - $(date)" > $RESULTS_FILE
echo "==========================================" >> $RESULTS_FILE
echo >> $RESULTS_FILE

# Test identical configuration as Phase 5
CONFIG="-h 127.0.0.1 -c 4 -s 16 -m 512 -l"
BENCHMARK="memtier_benchmark -h 127.0.0.1 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10"

echo "🔍 Test 1: Phase 5 Step 4A (Baseline - should show 1.197M ops/sec)"
echo "================================================================="
echo "Phase 5 Step 4A (Baseline):" >> $RESULTS_FILE
echo "============================" >> $RESULTS_FILE

if [ -f "./meteor_phase5_step4a_simd_lockfree_monitoring" ]; then
    ./meteor_phase5_step4a_simd_lockfree_monitoring $CONFIG -p 6380 > phase5_debug.log 2>&1 &
    PHASE5_PID=$!
    sleep 5
    
    if ps -p $PHASE5_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6380 > /dev/null; then
        echo "✅ Phase 5 server started"
        echo "🔥 Running Phase 5 benchmark..."
        
        if timeout 60 $BENCHMARK -p 6380 2>&1 | tee -a $RESULTS_FILE; then
            echo "✅ Phase 5 benchmark completed"
        else
            echo "❌ Phase 5 benchmark failed"
        fi
    else
        echo "❌ Phase 5 server failed to start"
        echo "Phase 5 startup failed" >> $RESULTS_FILE
    fi
    
    kill $PHASE5_PID 2>/dev/null || true
    sleep 3
else
    echo "❌ Phase 5 binary not found!"
    echo "Phase 5 binary not found" >> $RESULTS_FILE
fi

echo >> $RESULTS_FILE

echo
echo "🔍 Test 2: Phase 6 Step 1 (Current - showing regression)"
echo "========================================================"
echo "Phase 6 Step 1 (Current):" >> $RESULTS_FILE
echo "==========================" >> $RESULTS_FILE

./meteor_phase6_step1_avx512_numa $CONFIG -p 6381 > phase6_debug.log 2>&1 &
PHASE6_PID=$!
sleep 5

if ps -p $PHASE6_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6381 > /dev/null; then
    echo "✅ Phase 6 server started"
    echo "🔥 Running Phase 6 benchmark..."
    
    if timeout 60 $BENCHMARK -p 6381 2>&1 | tee -a $RESULTS_FILE; then
        echo "✅ Phase 6 benchmark completed"
    else
        echo "❌ Phase 6 benchmark failed"
    fi
else
    echo "❌ Phase 6 server failed to start"
    echo "Phase 6 startup failed" >> $RESULTS_FILE
fi

kill $PHASE6_PID 2>/dev/null || true
sleep 3

echo >> $RESULTS_FILE

echo
echo "📊 REGRESSION ANALYSIS"
echo "======================"
echo "Regression Analysis:" >> $RESULTS_FILE
echo "====================" >> $RESULTS_FILE

echo "🔍 Extracting ops/sec from both tests..."

# Extract Phase 5 results
PHASE5_OPS=$(grep "Totals" $RESULTS_FILE | head -1 | awk '{print $2}' 2>/dev/null || echo "N/A")
PHASE6_OPS=$(grep "Totals" $RESULTS_FILE | tail -1 | awk '{print $2}' 2>/dev/null || echo "N/A")

echo "Phase 5 Step 4A ops/sec: $PHASE5_OPS" | tee -a $RESULTS_FILE
echo "Phase 6 Step 1 ops/sec: $PHASE6_OPS" | tee -a $RESULTS_FILE

if [[ "$PHASE5_OPS" != "N/A" && "$PHASE6_OPS" != "N/A" ]]; then
    # Calculate regression percentage
    REGRESSION=$(echo "scale=2; (($PHASE5_OPS - $PHASE6_OPS) / $PHASE5_OPS) * 100" | bc -l 2>/dev/null || echo "N/A")
    echo "Performance regression: ${REGRESSION}%" | tee -a $RESULTS_FILE
    
    # Calculate slowdown factor
    SLOWDOWN=$(echo "scale=2; $PHASE5_OPS / $PHASE6_OPS" | bc -l 2>/dev/null || echo "N/A")
    echo "Phase 6 is ${SLOWDOWN}x slower than Phase 5" | tee -a $RESULTS_FILE
fi

echo >> $RESULTS_FILE

echo
echo "🔍 SUSPECTED ROOT CAUSES:"
echo "========================="
echo "Suspected Root Causes:" >> $RESULTS_FILE
echo "======================" >> $RESULTS_FILE

echo "1. NUMA overhead on single-node VM" | tee -a $RESULTS_FILE
echo "2. AVX-512 frequency throttling" | tee -a $RESULTS_FILE  
echo "3. Enhanced synchronization overhead" | tee -a $RESULTS_FILE
echo "4. Memory allocation pattern changes" | tee -a $RESULTS_FILE

echo >> $RESULTS_FILE

echo
echo "📋 Server Logs Analysis:"
echo "========================"
echo "Phase 5 startup (first 10 lines):"
head -10 phase5_debug.log 2>/dev/null || echo "No Phase 5 log"
echo
echo "Phase 6 startup (first 10 lines):"
head -10 phase6_debug.log 2>/dev/null || echo "No Phase 6 log"

echo
echo "🎯 NEXT STEPS:"
echo "=============="
echo "1. Create Phase 6 without NUMA optimizations"
echo "2. Create Phase 6 with AVX2 instead of AVX-512"
echo "3. Create Phase 6 with minimal synchronization"
echo "4. Test each variation to isolate the root cause"

echo
echo "📊 Results saved to: $RESULTS_FILE"