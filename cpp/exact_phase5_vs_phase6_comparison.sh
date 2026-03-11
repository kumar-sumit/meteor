#!/bin/bash

# **EXACT Phase 5 vs Phase 6 Benchmark Comparison**
# Use tmpfs to avoid disk space issues and run identical benchmarks

echo "🔥 EXACT Phase 5 vs Phase 6 Benchmark Comparison"
echo "================================================="
echo "Using IDENTICAL configuration that achieved 1,197,920 ops/sec"
echo "memtier_benchmark -h 127.0.0.1 -p PORT -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10"
echo "Server config: -h 127.0.0.1 -c 4 -s 16 -m 512 -l"
echo

# Use tmpfs for logs to avoid disk space issues
LOG_DIR="/tmp"
cd ~/meteor

# Kill any existing servers
pkill -f meteor 2>/dev/null || true
sleep 3

echo "📊 Test 1: Phase 5 Step 4A (Should show ~1.197M ops/sec)"
echo "========================================================"

# Check if Phase 5 binary exists
if [ ! -f "./meteor_phase5_step4a_simd_lockfree_monitoring" ]; then
    echo "❌ Phase 5 binary not found!"
    echo "Available binaries:"
    ls -la meteor_phase5* 2>/dev/null || echo "No Phase 5 binaries found"
    exit 1
fi

# Start Phase 5 server with EXACT config from original benchmark
echo "🚀 Starting Phase 5 server..."
./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6380 -c 4 -s 16 -m 512 -l > $LOG_DIR/phase5.log 2>&1 &
PHASE5_PID=$!

sleep 5

if ps -p $PHASE5_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6380 > /dev/null; then
    echo "✅ Phase 5 server started and listening on port 6380"
    
    echo "🔥 Running Phase 5 benchmark with EXACT original config..."
    echo "Expected result: ~1,197,920 ops/sec"
    echo
    
    # Run EXACT same benchmark as original - save to tmpfs
    timeout 60 memtier_benchmark -h 127.0.0.1 -p 6380 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 > $LOG_DIR/phase5_results.txt 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Phase 5 benchmark completed"
        echo
        echo "📊 Phase 5 Results:"
        echo "=================="
        grep -A 5 -B 5 "Totals" $LOG_DIR/phase5_results.txt || echo "Could not extract results"
    else
        echo "❌ Phase 5 benchmark failed or timed out"
        echo "Phase 5 benchmark output:"
        cat $LOG_DIR/phase5_results.txt
    fi
    
else
    echo "❌ Phase 5 server failed to start"
    echo "Phase 5 startup log:"
    cat $LOG_DIR/phase5.log
fi

# Stop Phase 5
kill $PHASE5_PID 2>/dev/null || true
sleep 3

echo
echo "📊 Test 2: Phase 6 Step 1 (Current regression suspect)"
echo "===================================================="

# Check if Phase 6 binary exists
if [ ! -f "./meteor_phase6_step1_avx512_numa" ]; then
    echo "❌ Phase 6 binary not found!"
    echo "Available binaries:"
    ls -la meteor_phase6* 2>/dev/null || echo "No Phase 6 binaries found"
    exit 1
fi

# Start Phase 6 server with IDENTICAL config
echo "🚀 Starting Phase 6 server..."
./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6381 -c 4 -s 16 -m 512 -l > $LOG_DIR/phase6.log 2>&1 &
PHASE6_PID=$!

sleep 8  # Give Phase 6 more time due to initialization

if ps -p $PHASE6_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6381 > /dev/null; then
    echo "✅ Phase 6 server started and listening on port 6381"
    
    echo "🔥 Running Phase 6 benchmark with IDENTICAL config..."
    echo "Expected result: Should match Phase 5 (~1.197M ops/sec) or show regression"
    echo
    
    # Run IDENTICAL benchmark - save to tmpfs
    timeout 60 memtier_benchmark -h 127.0.0.1 -p 6381 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 > $LOG_DIR/phase6_results.txt 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Phase 6 benchmark completed"
        echo
        echo "📊 Phase 6 Results:"
        echo "=================="
        grep -A 5 -B 5 "Totals" $LOG_DIR/phase6_results.txt || echo "Could not extract results"
    else
        echo "❌ Phase 6 benchmark failed or timed out"
        echo "Phase 6 benchmark output:"
        cat $LOG_DIR/phase6_results.txt
    fi
    
else
    echo "❌ Phase 6 server failed to start"
    echo "Phase 6 startup log:"
    cat $LOG_DIR/phase6.log
fi

# Stop Phase 6
kill $PHASE6_PID 2>/dev/null || true

echo
echo "🎯 COMPARISON SUMMARY"
echo "===================="
echo "Both tests used IDENTICAL configuration:"
echo "- Server: 4 cores, 16 shards, 512MB memory"
echo "- Benchmark: 2 threads, 5 connections, 10000 requests, pipeline=10"
echo "- Same ports, same parameters, same VM"
echo

# Extract and compare results
echo "📊 PERFORMANCE COMPARISON:"
echo "========================="

PHASE5_OPS=$(grep "Totals" $LOG_DIR/phase5_results.txt 2>/dev/null | awk '{print $2}' | head -1)
PHASE6_OPS=$(grep "Totals" $LOG_DIR/phase6_results.txt 2>/dev/null | awk '{print $2}' | head -1)

echo "Phase 5 Step 4A ops/sec: ${PHASE5_OPS:-'N/A'}"
echo "Phase 6 Step 1 ops/sec: ${PHASE6_OPS:-'N/A'}"

if [[ "$PHASE5_OPS" != "N/A" && "$PHASE6_OPS" != "N/A" && -n "$PHASE5_OPS" && -n "$PHASE6_OPS" ]]; then
    # Calculate regression if both values exist
    REGRESSION=$(echo "scale=2; (($PHASE5_OPS - $PHASE6_OPS) / $PHASE5_OPS) * 100" | bc -l 2>/dev/null || echo "N/A")
    SLOWDOWN=$(echo "scale=2; $PHASE5_OPS / $PHASE6_OPS" | bc -l 2>/dev/null || echo "N/A")
    
    echo "Performance change: -${REGRESSION}%"
    echo "Phase 6 is ${SLOWDOWN}x slower than Phase 5"
    
    # Determine verdict
    if (( $(echo "$REGRESSION > 50" | bc -l 2>/dev/null) )); then
        echo
        echo "🚨 VERDICT: MAJOR REGRESSION CONFIRMED"
        echo "Phase 6 Step 1 has significant performance issues"
    elif (( $(echo "$REGRESSION > 10" | bc -l 2>/dev/null) )); then
        echo
        echo "⚠️  VERDICT: MINOR REGRESSION DETECTED"
        echo "Phase 6 Step 1 has some performance degradation"
    else
        echo
        echo "✅ VERDICT: PERFORMANCE MAINTAINED"
        echo "Phase 6 Step 1 performs similarly to Phase 5"
    fi
else
    echo
    echo "❌ VERDICT: INCOMPLETE TEST"
    echo "Could not extract performance data from one or both tests"
fi

echo
echo "📋 Detailed logs available in:"
echo "- Phase 5 server: $LOG_DIR/phase5.log"
echo "- Phase 5 benchmark: $LOG_DIR/phase5_results.txt"
echo "- Phase 6 server: $LOG_DIR/phase6.log"
echo "- Phase 6 benchmark: $LOG_DIR/phase6_results.txt"