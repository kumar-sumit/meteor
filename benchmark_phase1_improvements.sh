#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== PHASE 1 OPTIMIZATION BENCHMARK ==="
echo "$(date): Benchmarking working optimized version vs baseline"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== BASELINE PERFORMANCE TEST ==="
echo "Starting baseline server..."
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_bench.log 2>&1 &
BASELINE_PID=$!
echo "Baseline server PID: $BASELINE_PID"
sleep 8

echo "Baseline performance test (10 seconds):"
timeout 10s sh -c '
count=0
start_time=$(date +%s.%N)
while true; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nkey%03d\r\n\$8\r\nbasevalue\r\n" $((count % 100)) | nc -w 1 127.0.0.1 6379 >/dev/null 2>&1 &&
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nkey%03d\r\n" $((count % 100)) | nc -w 1 127.0.0.1 6379 >/dev/null 2>&1 &&
    count=$((count + 1))
done
echo "Baseline operations completed: $count"' || true

kill $BASELINE_PID 2>/dev/null || true
sleep 3

echo ""
echo "=== OPTIMIZED PERFORMANCE TEST ==="  
echo "Starting optimized server (no ring buffer)..."
nohup ./cpp/meteor_phase1_fully_fixed -c 4 -s 4 > optimized_bench.log 2>&1 &
OPT_PID=$!
echo "Optimized server PID: $OPT_PID"
sleep 8

echo "Optimized performance test (10 seconds):"
timeout 10s sh -c '
count=0
start_time=$(date +%s.%N)  
while true; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nkey%03d\r\n\$7\r\noptval\r\n" $((count % 100)) | nc -w 1 127.0.0.1 6379 >/dev/null 2>&1 &&
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nkey%03d\r\n" $((count % 100)) | nc -w 1 127.0.0.1 6379 >/dev/null 2>&1 &&
    count=$((count + 1))
done
echo "Optimized operations completed: $count"' || true

kill $OPT_PID 2>/dev/null || true

echo ""
echo "=== PHASE 1 OPTIMIZATION RESULTS ==="
echo "📊 Compare the operation counts above"
echo "🎯 Optimized version should show higher throughput due to:"
echo "   ✅ Fixed GET response processing"
echo "   ✅ Improved string handling" 
echo "   ✅ Better cross-core command routing"
echo "   ✅ Optimized batch processing"
echo ""
echo "📝 Note: Ring buffer optimization still needs debugging (separate task)"
echo ""
echo "$(date): Phase 1 benchmark complete"












