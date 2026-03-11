#!/bin/bash

echo "🔥 PHASE 6 OPTIMIZED vs PHASE 5 COMPARISON TEST"
echo "==============================================="
echo "Testing optimized Phase 6 with smart NUMA and reduced latency"
echo "Date: $(date)"
echo

cd ~/meteor

# Clean up any existing processes
echo "🧹 Cleaning up existing processes..."
pkill -f meteor 2>/dev/null || true
sudo pkill -9 -f meteor 2>/dev/null || true
sleep 3

# Kill anything on our test ports
for port in 6379 6380 6381 6382; do
    fuser -k ${port}/tcp 2>/dev/null || true
    sudo fuser -k ${port}/tcp 2>/dev/null || true
done
sleep 3

echo "✅ Cleanup complete"
echo

# EXACT benchmark parameters that achieved 1.2M RPS
BENCH_PARAMS="-t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000"

echo "📊 System Information:"
echo "====================="
echo "CPU cores: $(nproc)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "NUMA nodes: $(numactl --hardware | grep available | awk '{print $2}' || echo 'N/A')"
echo

echo "📊 TEST 1: Phase 5 Step 4A (Baseline) on Port 6380"
echo "=================================================="
echo "Starting Phase 5 server on port 6380..."

timeout 120 ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6380 -c 4 -s 16 -m 512 -l > /tmp/phase5_test.log 2>&1 &
P5_PID=$!

echo "Waiting for Phase 5 to initialize..."
sleep 8

# Check if Phase 5 is running and listening
if ps -p $P5_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6380 > /dev/null; then
    echo "✅ Phase 5 server ready on port 6380"
    
    echo "🔥 Running benchmark on Phase 5..."
    echo "Command: memtier_benchmark -h 127.0.0.1 -p 6380 $BENCH_PARAMS"
    echo
    
    timeout 120 memtier_benchmark -h 127.0.0.1 -p 6380 $BENCH_PARAMS > /tmp/phase5_bench.txt 2>&1
    BENCH_EXIT_CODE=$?
    
    if [ $BENCH_EXIT_CODE -eq 0 ]; then
        echo "✅ Phase 5 benchmark completed"
        echo
        echo "📊 PHASE 5 RESULTS:"
        echo "=================="
        grep -A 3 -B 1 "Totals" /tmp/phase5_bench.txt || echo "Could not find Totals line"
        echo
        
        # Extract key metrics
        P5_OPS=$(grep "Totals" /tmp/phase5_bench.txt 2>/dev/null | awk '{print $2}' | head -1)
        P5_LATENCY=$(grep "Totals" /tmp/phase5_bench.txt 2>/dev/null | awk '{print $6}' | head -1)
        echo "📈 Phase 5: ${P5_OPS:-N/A} ops/sec, ${P5_LATENCY:-N/A} ms avg latency"
        
    else
        echo "❌ Phase 5 benchmark failed (exit code: $BENCH_EXIT_CODE)"
        echo "Last 20 lines of benchmark output:"
        tail -20 /tmp/phase5_bench.txt
    fi
    
else
    echo "❌ Phase 5 server not ready"
    echo "Phase 5 server log:"
    tail -20 /tmp/phase5_test.log
fi

# Clean up Phase 5
echo "🧹 Stopping Phase 5..."
kill $P5_PID 2>/dev/null || true
sleep 3
fuser -k 6380/tcp 2>/dev/null || true
sleep 2

echo
echo "📊 TEST 2: Phase 6 Step 1 Optimized on Port 6381"
echo "=============================================="
echo "Starting Phase 6 optimized server on port 6381..."

timeout 120 ./meteor_phase6_step1_optimized -h 127.0.0.1 -p 6381 -c 4 -s 16 -m 512 -l > /tmp/phase6_test.log 2>&1 &
P6_PID=$!

echo "Waiting for Phase 6 optimized to initialize (should be faster now)..."
sleep 6  # Reduced from 10s due to optimizations

# Check if Phase 6 is running and listening
if ps -p $P6_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6381 > /dev/null; then
    echo "✅ Phase 6 optimized server ready on port 6381"
    
    echo "🔥 Running benchmark on Phase 6 optimized..."
    echo "Command: memtier_benchmark -h 127.0.0.1 -p 6381 $BENCH_PARAMS"
    echo
    
    timeout 120 memtier_benchmark -h 127.0.0.1 -p 6381 $BENCH_PARAMS > /tmp/phase6_bench.txt 2>&1
    BENCH_EXIT_CODE=$?
    
    if [ $BENCH_EXIT_CODE -eq 0 ]; then
        echo "✅ Phase 6 benchmark completed"
        echo
        echo "📊 PHASE 6 OPTIMIZED RESULTS:"
        echo "============================"
        grep -A 3 -B 1 "Totals" /tmp/phase6_bench.txt || echo "Could not find Totals line"
        echo
        
        # Extract key metrics
        P6_OPS=$(grep "Totals" /tmp/phase6_bench.txt 2>/dev/null | awk '{print $2}' | head -1)
        P6_LATENCY=$(grep "Totals" /tmp/phase6_bench.txt 2>/dev/null | awk '{print $6}' | head -1)
        echo "📈 Phase 6 Optimized: ${P6_OPS:-N/A} ops/sec, ${P6_LATENCY:-N/A} ms avg latency"
        
    else
        echo "❌ Phase 6 benchmark failed (exit code: $BENCH_EXIT_CODE)"
        echo "Last 20 lines of benchmark output:"
        tail -20 /tmp/phase6_bench.txt
    fi
    
else
    echo "❌ Phase 6 optimized server not ready"
    echo "Phase 6 server log:"
    tail -20 /tmp/phase6_test.log
fi

# Clean up Phase 6
echo "🧹 Stopping Phase 6..."
kill $P6_PID 2>/dev/null || true
sleep 3
fuser -k 6381/tcp 2>/dev/null || true

echo
echo "🎯 FINAL COMPARISON"
echo "=================="
echo "Benchmark Parameters Used (exact 1.2M RPS config):"
echo "  $BENCH_PARAMS"
echo
echo "Results Summary:"
echo "  Phase 5 Step 4A (baseline):     ${P5_OPS:-N/A} ops/sec, ${P5_LATENCY:-N/A} ms latency"
echo "  Phase 6 Step 1 (optimized):     ${P6_OPS:-N/A} ops/sec, ${P6_LATENCY:-N/A} ms latency"
echo

# Calculate performance comparison if both tests succeeded
if [[ -n "$P5_OPS" && -n "$P6_OPS" && "$P5_OPS" != "N/A" && "$P6_OPS" != "N/A" ]]; then
    # Remove any commas from numbers for calculation
    P5_CLEAN=$(echo "$P5_OPS" | tr -d ',')
    P6_CLEAN=$(echo "$P6_OPS" | tr -d ',')
    
    if command -v bc >/dev/null 2>&1; then
        RATIO=$(echo "scale=3; $P6_CLEAN / $P5_CLEAN" | bc -l 2>/dev/null || echo "N/A")
        DIFF_PERCENT=$(echo "scale=1; (($P6_CLEAN - $P5_CLEAN) / $P5_CLEAN) * 100" | bc -l 2>/dev/null || echo "N/A")
        
        echo "Performance Analysis:"
        echo "  Phase 6 / Phase 5 ratio: ${RATIO}x"
        echo "  Performance change: ${DIFF_PERCENT}%"
        echo
        
        # Determine verdict with focus on reaching 1.2M RPS
        if (( $(echo "$P5_CLEAN > 1000000" | bc -l 2>/dev/null) )); then
            echo "✅ PHASE 5: HIGH PERFORMANCE CONFIRMED (>1M RPS)"
            if (( $(echo "$P6_CLEAN > 1000000" | bc -l 2>/dev/null) )); then
                echo "✅ PHASE 6 OPTIMIZED: HIGH PERFORMANCE MAINTAINED (>1M RPS)"
                if (( $(echo "$P6_CLEAN > $P5_CLEAN" | bc -l 2>/dev/null) )); then
                    echo "🚀 VERDICT: OPTIMIZATION SUCCESS - Phase 6 outperforms Phase 5!"
                else
                    echo "✅ VERDICT: NO REGRESSION - Both versions perform excellently"
                fi
            else
                echo "❌ PHASE 6 OPTIMIZED: Still below 1M RPS target"
                echo "🔧 VERDICT: Further optimization needed"
            fi
        else
            echo "⚠️  PHASE 5: Below expected 1.2M RPS performance"
            if (( $(echo "$P6_CLEAN > $P5_CLEAN" | bc -l 2>/dev/null) )); then
                echo "✅ PHASE 6 OPTIMIZED: Shows improvement over Phase 5"
                echo "🤔 VERDICT: Environment may be limiting both versions"
            else
                echo "❌ PHASE 6 OPTIMIZED: No improvement shown"
                echo "🔧 VERDICT: Need to investigate further optimizations"
            fi
        fi
    else
        echo "Performance Analysis: bc not available for calculations"
    fi
else
    echo "❌ VERDICT: INCOMPLETE TEST - Could not compare performance"
fi

echo
echo "🔍 OPTIMIZATION ANALYSIS:"
echo "========================"
echo "Phase 6 Optimizations Applied:"
echo "✅ Smart NUMA: Only enabled when nodes > 1"
echo "✅ Reduced sync delays: 100ms → 10ms thread start delay"
echo "✅ Faster initialization: 2000ms → 500ms final wait"
echo "✅ AVX-512 SIMD: 8-way parallel vs 4-way AVX2"
echo "✅ Maintained all Phase 5 optimizations"
echo

if [[ "$P5_OPS" != "N/A" && "$P6_OPS" != "N/A" ]]; then
    P5_NUM=$(echo "$P5_OPS" | tr -d ',')
    P6_NUM=$(echo "$P6_OPS" | tr -d ',')
    
    if (( $(echo "$P5_NUM < 100000" | bc -l 2>/dev/null) )); then
        echo "🚨 CRITICAL: Both versions significantly underperforming vs 1.2M RPS target"
        echo "   Possible causes:"
        echo "   - VM resource constraints"
        echo "   - Network/disk bottlenecks"
        echo "   - Different test environment than original 1.2M test"
        echo "   - Need to investigate system-level optimizations"
    fi
fi

echo
echo "📁 Detailed logs available:"
echo "  Phase 5 server: /tmp/phase5_test.log"
echo "  Phase 5 benchmark: /tmp/phase5_bench.txt"
echo "  Phase 6 server: /tmp/phase6_test.log"
echo "  Phase 6 benchmark: /tmp/phase6_bench.txt"
echo
echo "Test completed at: $(date)"