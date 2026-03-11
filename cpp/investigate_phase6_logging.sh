#!/bin/bash

echo "🔍 INVESTIGATING PHASE 6 LOGGING AND PERFORMANCE"
echo "==============================================="
echo "Date: $(date)"
echo

cd ~/meteor

# Clean up
echo "🧹 Cleaning up processes and ports..."
pkill -f meteor 2>/dev/null || true
fuser -k 6379/tcp 2>/dev/null || true
sleep 3

# Check binary sizes and details
echo "📊 Binary Analysis:"
echo "=================="
ls -lh meteor_phase5_step4a_simd_lockfree_monitoring meteor_phase6_step1_avx512_numa 2>/dev/null || echo "Binaries not found"
echo

# Test 1: Check Phase 5 startup logging
echo "🔍 TEST 1: Phase 5 Step 4A Startup Analysis"
echo "==========================================="
echo "Starting Phase 5 server and capturing startup output..."

timeout 10 ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l > /tmp/phase5_startup.log 2>&1 &
P5_PID=$!
sleep 5

if ps -p $P5_PID > /dev/null; then
    echo "✅ Phase 5 server started (PID: $P5_PID)"
    echo "📏 Phase 5 startup log size:"
    wc -l /tmp/phase5_startup.log
    echo "📝 Phase 5 startup log content:"
    head -20 /tmp/phase5_startup.log
    echo "..."
    tail -10 /tmp/phase5_startup.log
else
    echo "❌ Phase 5 server failed to start"
    cat /tmp/phase5_startup.log
fi

kill $P5_PID 2>/dev/null || true
sleep 3

echo
echo "🔍 TEST 2: Phase 6 Step 1 Startup Analysis"
echo "=========================================="
echo "Starting Phase 6 server and capturing startup output..."

timeout 15 ./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l > /tmp/phase6_startup.log 2>&1 &
P6_PID=$!
sleep 8

if ps -p $P6_PID > /dev/null; then
    echo "✅ Phase 6 server started (PID: $P6_PID)"
    echo "📏 Phase 6 startup log size:"
    wc -l /tmp/phase6_startup.log
    echo "📝 Phase 6 startup log content:"
    head -20 /tmp/phase6_startup.log
    echo "..."
    tail -10 /tmp/phase6_startup.log
else
    echo "❌ Phase 6 server failed to start"
    echo "📝 Phase 6 startup failure log:"
    cat /tmp/phase6_startup.log
fi

kill $P6_PID 2>/dev/null || true
fuser -k 6379/tcp 2>/dev/null || true
sleep 3

echo
echo "📊 LOGGING COMPARISON"
echo "===================="
P5_LINES=$(wc -l < /tmp/phase5_startup.log 2>/dev/null || echo 0)
P6_LINES=$(wc -l < /tmp/phase6_startup.log 2>/dev/null || echo 0)

echo "Phase 5 startup log lines: $P5_LINES"
echo "Phase 6 startup log lines: $P6_LINES"

if [ "$P6_LINES" -gt "$P5_LINES" ]; then
    RATIO=$((P6_LINES * 100 / P5_LINES))
    echo "⚠️  Phase 6 produces ${RATIO}% more startup logging than Phase 5"
    echo "   This could impact performance and disk usage"
else
    echo "✅ Phase 6 logging is reasonable compared to Phase 5"
fi

echo
echo "🔍 TEST 3: Runtime Logging During Benchmark"
echo "==========================================="

# Test Phase 5 runtime logging
echo "📊 Phase 5 runtime logging test..."
./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l > /tmp/phase5_runtime.log 2>&1 &
P5_PID=$!
sleep 5

if ps -p $P5_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6379 > /dev/null; then
    echo "✅ Phase 5 server ready"
    
    # Get initial log size
    P5_INITIAL_SIZE=$(wc -l < /tmp/phase5_runtime.log)
    
    echo "🔥 Running short benchmark on Phase 5..."
    timeout 30 memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 5000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000 > /tmp/phase5_bench_result.txt 2>&1
    
    # Get final log size
    P5_FINAL_SIZE=$(wc -l < /tmp/phase5_runtime.log)
    P5_RUNTIME_LINES=$((P5_FINAL_SIZE - P5_INITIAL_SIZE))
    
    echo "📏 Phase 5 runtime logging during benchmark: $P5_RUNTIME_LINES lines"
    
    # Extract performance
    P5_OPS=$(grep "Totals" /tmp/phase5_bench_result.txt 2>/dev/null | awk '{print $2}' | head -1)
    echo "📊 Phase 5 performance: ${P5_OPS:-N/A} ops/sec"
    
else
    echo "❌ Phase 5 server not ready"
    tail -10 /tmp/phase5_runtime.log
fi

kill $P5_PID 2>/dev/null || true
fuser -k 6379/tcp 2>/dev/null || true
sleep 3

# Test Phase 6 runtime logging
echo
echo "📊 Phase 6 runtime logging test..."
./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l > /tmp/phase6_runtime.log 2>&1 &
P6_PID=$!
sleep 8

if ps -p $P6_PID > /dev/null && ss -tlnp 2>/dev/null | grep :6379 > /dev/null; then
    echo "✅ Phase 6 server ready"
    
    # Get initial log size
    P6_INITIAL_SIZE=$(wc -l < /tmp/phase6_runtime.log)
    
    echo "🔥 Running short benchmark on Phase 6..."
    timeout 30 memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 5000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000 > /tmp/phase6_bench_result.txt 2>&1
    
    # Get final log size
    P6_FINAL_SIZE=$(wc -l < /tmp/phase6_runtime.log)
    P6_RUNTIME_LINES=$((P6_FINAL_SIZE - P6_INITIAL_SIZE))
    
    echo "📏 Phase 6 runtime logging during benchmark: $P6_RUNTIME_LINES lines"
    
    # Extract performance
    P6_OPS=$(grep "Totals" /tmp/phase6_bench_result.txt 2>/dev/null | awk '{print $2}' | head -1)
    echo "📊 Phase 6 performance: ${P6_OPS:-N/A} ops/sec"
    
else
    echo "❌ Phase 6 server not ready"
    tail -10 /tmp/phase6_runtime.log
fi

kill $P6_PID 2>/dev/null || true
fuser -k 6379/tcp 2>/dev/null || true

echo
echo "🎯 FINAL ANALYSIS"
echo "================"
echo "Startup Logging:"
echo "  Phase 5: $P5_LINES lines"
echo "  Phase 6: $P6_LINES lines"
echo
echo "Runtime Logging (during benchmark):"
echo "  Phase 5: ${P5_RUNTIME_LINES:-N/A} lines"
echo "  Phase 6: ${P6_RUNTIME_LINES:-N/A} lines"
echo
echo "Performance (with correct parameters):"
echo "  Phase 5: ${P5_OPS:-N/A} ops/sec"
echo "  Phase 6: ${P6_OPS:-N/A} ops/sec"
echo

# Check for excessive logging patterns
echo "🔍 Checking for excessive logging patterns in Phase 6..."
if [ -f /tmp/phase6_runtime.log ]; then
    echo "Most frequent log patterns in Phase 6:"
    grep -o "^[^:]*:" /tmp/phase6_runtime.log | sort | uniq -c | sort -nr | head -10
fi

echo
echo "💡 RECOMMENDATIONS:"
if [ "${P6_RUNTIME_LINES:-0}" -gt "${P5_RUNTIME_LINES:-0}" ] && [ "${P6_RUNTIME_LINES:-0}" -gt 100 ]; then
    echo "⚠️  Phase 6 has excessive runtime logging ($P6_RUNTIME_LINES vs $P5_RUNTIME_LINES lines)"
    echo "   This could significantly impact performance and disk usage"
    echo "   Consider reducing log verbosity in Phase 6"
else
    echo "✅ Phase 6 logging levels appear reasonable"
fi

echo
echo "📁 Log files saved in /tmp/ for detailed analysis"
echo "Investigation complete at $(date)"