#!/bin/bash

echo "🔥 PHASE 5 vs PHASE 6 BENCHMARK COMPARISON"
echo "=========================================="
echo "Using EXACT parameters that achieved 1.197M RPS"
echo "Date: $(date)"
echo

cd ~/meteor

# Clean up any existing processes
echo "🧹 Cleaning up existing processes..."
pkill -f meteor 2>/dev/null || true
sudo pkill -9 -f meteor 2>/dev/null || true
sleep 3

# Kill anything on our test ports
for port in 6379 6380 6381; do
    fuser -k ${port}/tcp 2>/dev/null || true
    sudo fuser -k ${port}/tcp 2>/dev/null || true
done
sleep 3

echo "✅ Cleanup complete"
echo

# EXACT benchmark parameters that achieved 1.197M RPS
BENCH_PARAMS="-t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000"

echo "📊 TEST 1: Phase 5 Step 4A on Port 6380"
echo "======================================="
echo "Starting Phase 5 server on port 6380..."

./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6380 -c 4 -s 16 -m 512 -l > /tmp/phase5_port6380.log 2>&1 &
P5_PID=$!

echo "Waiting for Phase 5 to initialize..."
sleep 6

# Check if Phase 5 is running and listening
if ps -p $P5_PID > /dev/null; then
    echo "✅ Phase 5 process is running (PID: $P5_PID)"
    
    # Wait a bit more and check if it's listening
    sleep 2
    if ss -tlnp 2>/dev/null | grep :6380 > /dev/null; then
        echo "✅ Phase 5 is listening on port 6380"
        
        echo "🔥 Running EXACT benchmark on Phase 5..."
        echo "Command: memtier_benchmark -h 127.0.0.1 -p 6380 $BENCH_PARAMS"
        echo
        
        timeout 90 memtier_benchmark -h 127.0.0.1 -p 6380 $BENCH_PARAMS > /tmp/phase5_bench_results.txt 2>&1
        BENCH_EXIT_CODE=$?
        
        if [ $BENCH_EXIT_CODE -eq 0 ]; then
            echo "✅ Phase 5 benchmark completed successfully"
            echo
            echo "📊 PHASE 5 RESULTS:"
            echo "=================="
            grep -A 3 -B 1 "Totals" /tmp/phase5_bench_results.txt || echo "Could not find Totals line"
            echo
            
            # Extract key metrics
            P5_OPS=$(grep "Totals" /tmp/phase5_bench_results.txt 2>/dev/null | awk '{print $2}' | head -1)
            P5_LATENCY=$(grep "Totals" /tmp/phase5_bench_results.txt 2>/dev/null | awk '{print $6}' | head -1)
            echo "📈 Phase 5 Performance: ${P5_OPS:-N/A} ops/sec, ${P5_LATENCY:-N/A} ms avg latency"
            
        else
            echo "❌ Phase 5 benchmark failed or timed out (exit code: $BENCH_EXIT_CODE)"
            echo "Phase 5 benchmark output:"
            tail -20 /tmp/phase5_bench_results.txt
        fi
        
    else
        echo "❌ Phase 5 is not listening on port 6380"
        echo "Checking what's using port 6380:"
        ss -tlnp | grep :6380 || echo "Nothing found on port 6380"
    fi
    
else
    echo "❌ Phase 5 process died"
    echo "Phase 5 server log:"
    cat /tmp/phase5_port6380.log
fi

# Clean up Phase 5
echo "🧹 Stopping Phase 5..."
kill $P5_PID 2>/dev/null || true
sleep 3
fuser -k 6380/tcp 2>/dev/null || true
sleep 2

echo
echo "📊 TEST 2: Phase 6 Step 1 on Port 6381"
echo "======================================"
echo "Starting Phase 6 server on port 6381..."

./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6381 -c 4 -s 16 -m 512 -l > /tmp/phase6_port6381.log 2>&1 &
P6_PID=$!

echo "Waiting for Phase 6 to initialize (longer wait for NUMA setup)..."
sleep 10

# Check if Phase 6 is running and listening
if ps -p $P6_PID > /dev/null; then
    echo "✅ Phase 6 process is running (PID: $P6_PID)"
    
    # Wait a bit more and check if it's listening
    sleep 3
    if ss -tlnp 2>/dev/null | grep :6381 > /dev/null; then
        echo "✅ Phase 6 is listening on port 6381"
        
        echo "🔥 Running EXACT benchmark on Phase 6..."
        echo "Command: memtier_benchmark -h 127.0.0.1 -p 6381 $BENCH_PARAMS"
        echo
        
        timeout 90 memtier_benchmark -h 127.0.0.1 -p 6381 $BENCH_PARAMS > /tmp/phase6_bench_results.txt 2>&1
        BENCH_EXIT_CODE=$?
        
        if [ $BENCH_EXIT_CODE -eq 0 ]; then
            echo "✅ Phase 6 benchmark completed successfully"
            echo
            echo "📊 PHASE 6 RESULTS:"
            echo "=================="
            grep -A 3 -B 1 "Totals" /tmp/phase6_bench_results.txt || echo "Could not find Totals line"
            echo
            
            # Extract key metrics
            P6_OPS=$(grep "Totals" /tmp/phase6_bench_results.txt 2>/dev/null | awk '{print $2}' | head -1)
            P6_LATENCY=$(grep "Totals" /tmp/phase6_bench_results.txt 2>/dev/null | awk '{print $6}' | head -1)
            echo "📈 Phase 6 Performance: ${P6_OPS:-N/A} ops/sec, ${P6_LATENCY:-N/A} ms avg latency"
            
        else
            echo "❌ Phase 6 benchmark failed or timed out (exit code: $BENCH_EXIT_CODE)"
            echo "Phase 6 benchmark output:"
            tail -20 /tmp/phase6_bench_results.txt
        fi
        
    else
        echo "❌ Phase 6 is not listening on port 6381"
        echo "Checking what's using port 6381:"
        ss -tlnp | grep :6381 || echo "Nothing found on port 6381"
    fi
    
else
    echo "❌ Phase 6 process died"
    echo "Phase 6 server log:"
    cat /tmp/phase6_port6381.log
fi

# Clean up Phase 6
echo "🧹 Stopping Phase 6..."
kill $P6_PID 2>/dev/null || true
sleep 3
fuser -k 6381/tcp 2>/dev/null || true

echo
echo "🎯 FINAL COMPARISON"
echo "=================="
echo "Benchmark Parameters Used:"
echo "  $BENCH_PARAMS"
echo
echo "Results Summary:"
echo "  Phase 5 Step 4A (port 6380): ${P5_OPS:-N/A} ops/sec, ${P5_LATENCY:-N/A} ms latency"
echo "  Phase 6 Step 1 (port 6381): ${P6_OPS:-N/A} ops/sec, ${P6_LATENCY:-N/A} ms latency"
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
        
        # Determine verdict
        if (( $(echo "$P5_CLEAN > 1000000" | bc -l 2>/dev/null) )); then
            echo "✅ PHASE 5: HIGH PERFORMANCE CONFIRMED (>1M RPS)"
            if (( $(echo "$P6_CLEAN > 1000000" | bc -l 2>/dev/null) )); then
                echo "✅ PHASE 6: HIGH PERFORMANCE MAINTAINED (>1M RPS)"
                if (( $(echo "$RATIO > 0.95" | bc -l 2>/dev/null) )); then
                    echo "🎉 VERDICT: NO SIGNIFICANT REGRESSION - Phase 6 performs well!"
                else
                    echo "⚠️  VERDICT: MINOR REGRESSION - Phase 6 is slower but still high performance"
                fi
            else
                echo "❌ PHASE 6: PERFORMANCE REGRESSION (<1M RPS)"
                echo "🚨 VERDICT: SIGNIFICANT REGRESSION - Phase 6 needs investigation"
            fi
        else
            echo "❌ PHASE 5: LOWER THAN EXPECTED PERFORMANCE (<1M RPS)"
            if (( $(echo "$P6_CLEAN > $P5_CLEAN" | bc -l 2>/dev/null) )); then
                echo "✅ PHASE 6: BETTER THAN PHASE 5"
                echo "🤔 VERDICT: Both below expected, but Phase 6 shows improvement"
            else
                echo "❌ PHASE 6: ALSO LOWER PERFORMANCE"
                echo "🤔 VERDICT: Both versions underperforming - environment issue?"
            fi
        fi
    else
        echo "Performance Analysis: bc not available for calculations"
    fi
else
    echo "❌ VERDICT: INCOMPLETE TEST - Could not compare performance"
    if [[ "$P5_OPS" == "N/A" ]]; then
        echo "   Phase 5 test failed"
    fi
    if [[ "$P6_OPS" == "N/A" ]]; then
        echo "   Phase 6 test failed"
    fi
fi

echo
echo "📋 Key Insights:"
echo "✅ Used EXACT parameters that originally achieved 1.197M RPS"
echo "✅ Tested on separate ports to avoid conflicts"
echo "✅ Servers ran with identical configurations (4 cores, 16 shards, 512MB)"
echo
echo "📁 Detailed logs available:"
echo "  Phase 5 server: /tmp/phase5_port6380.log"
echo "  Phase 5 benchmark: /tmp/phase5_bench_results.txt"
echo "  Phase 6 server: /tmp/phase6_port6381.log"
echo "  Phase 6 benchmark: /tmp/phase6_bench_results.txt"
echo
echo "Test completed at: $(date)"