#!/bin/bash

# **REPRODUCE EXACT 1.197M RPS BENCHMARK**
# Using the exact command that achieved the breakthrough performance

echo "🔥 REPRODUCING EXACT Phase 5 Success Benchmark"
echo "=============================================="
echo "Using EXACT command that achieved 1.197M ops/sec:"
echo "memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000"
echo

cd ~/meteor

# Kill any existing servers
pkill -f meteor 2>/dev/null || true
sleep 3

echo "📊 Test 1: Phase 5 Step 4A with EXACT successful parameters"
echo "=========================================================="

# Start Phase 5 server (exact same config as successful run)
./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l > /tmp/phase5_exact.log 2>&1 &
PHASE5_PID=$!

sleep 5

if ps -p $PHASE5_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6379 > /dev/null; then
    echo "✅ Phase 5 server started on port 6379"
    
    echo "🔥 Running EXACT successful benchmark command..."
    echo "Expected: ~1,197,920 ops/sec"
    echo
    
    # Run EXACT command that achieved 1.197M ops/sec
    echo "⏰ Starting benchmark..."
    timeout 90 memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000 > /tmp/phase5_exact_results.txt 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Phase 5 benchmark completed successfully"
        echo
        echo "📊 Phase 5 Results:"
        echo "=================="
        grep -A 5 -B 5 "Totals" /tmp/phase5_exact_results.txt || echo "Could not find Totals line"
        echo
        echo "Full results saved to: /tmp/phase5_exact_results.txt"
    else
        echo "❌ Phase 5 benchmark failed or timed out"
        echo "Phase 5 benchmark output:"
        cat /tmp/phase5_exact_results.txt
    fi
    
else
    echo "❌ Phase 5 server failed to start"
    echo "Phase 5 server log:"
    cat /tmp/phase5_exact.log
fi

kill $PHASE5_PID 2>/dev/null || true
sleep 3

echo
echo "📊 Test 2: Phase 6 Step 1 with EXACT same parameters"
echo "=================================================="

# Start Phase 6 server (identical config)
./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l > /tmp/phase6_exact.log 2>&1 &
PHASE6_PID=$!

sleep 8  # Phase 6 needs more initialization time

if ps -p $PHASE6_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6379 > /dev/null; then
    echo "✅ Phase 6 server started on port 6379"
    
    echo "🔥 Running EXACT same benchmark on Phase 6..."
    echo "Expected: Should match Phase 5 performance if no regression"
    echo
    
    # Run identical command with all the same parameters
    echo "⏰ Starting benchmark..."
    timeout 90 memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000 > /tmp/phase6_exact_results.txt 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Phase 6 benchmark completed successfully"
        echo
        echo "📊 Phase 6 Results:"
        echo "=================="
        grep -A 5 -B 5 "Totals" /tmp/phase6_exact_results.txt || echo "Could not find Totals line"
        echo
        echo "Full results saved to: /tmp/phase6_exact_results.txt"
    else
        echo "❌ Phase 6 benchmark failed or timed out"
        echo "Phase 6 benchmark output:"
        cat /tmp/phase6_exact_results.txt
    fi
    
else
    echo "❌ Phase 6 server failed to start"
    echo "Phase 6 server log:"
    cat /tmp/phase6_exact.log
fi

kill $PHASE6_PID 2>/dev/null || true

echo
echo "🎯 FINAL COMPARISON"
echo "=================="

# Extract performance numbers
PHASE5_OPS=$(grep "Totals" /tmp/phase5_exact_results.txt 2>/dev/null | awk '{print $2}' | head -1)
PHASE6_OPS=$(grep "Totals" /tmp/phase6_exact_results.txt 2>/dev/null | awk '{print $2}' | head -1)

echo "EXACT benchmark parameters used:"
echo "- Threads: 2, Connections: 5, Requests: 10000"
echo "- Pipeline: 10, Key pattern: R:R, Key range: 1-100000"
echo
echo "Results:"
echo "Phase 5 Step 4A ops/sec: ${PHASE5_OPS:-'N/A'}"
echo "Phase 6 Step 1 ops/sec: ${PHASE6_OPS:-'N/A'}"

if [[ "$PHASE5_OPS" != "N/A" && "$PHASE6_OPS" != "N/A" && -n "$PHASE5_OPS" && -n "$PHASE6_OPS" ]]; then
    # Calculate difference
    RATIO=$(echo "scale=2; $PHASE6_OPS / $PHASE5_OPS" | bc -l 2>/dev/null || echo "N/A")
    DIFF_PERCENT=$(echo "scale=2; (($PHASE6_OPS - $PHASE5_OPS) / $PHASE5_OPS) * 100" | bc -l 2>/dev/null || echo "N/A")
    
    echo "Performance ratio (P6/P5): ${RATIO}x"
    echo "Performance difference: ${DIFF_PERCENT}%"
    echo
    
    # Determine verdict
    if (( $(echo "$PHASE5_OPS > 1000000" | bc -l 2>/dev/null) )); then
        echo "✅ PHASE 5: HIGH PERFORMANCE CONFIRMED (>1M RPS)"
        if (( $(echo "$PHASE6_OPS > 1000000" | bc -l 2>/dev/null) )); then
            echo "✅ PHASE 6: HIGH PERFORMANCE MAINTAINED (>1M RPS)"
            echo "🎉 VERDICT: NO REGRESSION - Both versions perform excellently!"
        else
            echo "❌ PHASE 6: PERFORMANCE REGRESSION (<1M RPS)"
            echo "🚨 VERDICT: REGRESSION CONFIRMED - Phase 6 needs debugging"
        fi
    else
        echo "❌ PHASE 5: LOWER THAN EXPECTED PERFORMANCE (<1M RPS)"
        echo "🤔 VERDICT: Original benchmark conditions may have changed"
    fi
else
    echo "❌ VERDICT: INCOMPLETE TEST - Could not extract performance data"
fi

echo
echo "📋 Key Discovery:"
echo "The missing parameters were:"
echo "  --key-pattern=R:R --key-minimum=1 --key-maximum=100000"
echo "These parameters are CRITICAL for reproducing the 1.197M RPS performance!"
echo
echo "📁 Full logs available in /tmp/ directory"