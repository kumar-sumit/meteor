#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== PHASE 1 OPTIMIZATION BENCHMARK ==="
echo "$(date): Starting benchmark tests"

# Kill any running servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== BASELINE SERVER TEST ==="
echo "Starting baseline server..."
nohup ./cpp/meteor_single_command_fixed -c 4 -s 4 > baseline_server.log 2>&1 &
BASELINE_PID=$!
echo "Baseline server PID: $BASELINE_PID"
sleep 8

echo "Testing baseline performance..."
START_TIME=$(date +%s.%N)
for i in {1..200}; do
    printf "*3\r\n\$3\r\nSET\r\n\$13\r\nbaseline:key$i\r\n\$14\r\nbaseline:val$i\r\n" | nc -w 1 127.0.0.1 6379 > /dev/null 2>&1
done
END_TIME=$(date +%s.%N)
BASELINE_TIME=$(echo "$END_TIME - $START_TIME" | bc -l)

echo "✅ Baseline: 200 commands in ${BASELINE_TIME}s"
echo "✅ Baseline QPS: $(echo "scale=0; 200 / $BASELINE_TIME" | bc -l)"

# Test correctness
echo "Testing baseline correctness..."
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncorrect:base\r\n\$9\r\nbaseline\r\n" | nc -w 2 127.0.0.1 6379
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncorrect:base\r\n" | nc -w 2 127.0.0.1 6379

kill $BASELINE_PID 2>/dev/null || true
sleep 3

echo ""
echo "=== PHASE 1 OPTIMIZED SERVER TEST ==="
echo "Starting Phase 1 optimized server..."
nohup ./cpp/meteor_single_command_optimized_v1 -c 4 -s 4 > phase1_server.log 2>&1 &
PHASE1_PID=$!
echo "Phase 1 server PID: $PHASE1_PID"
sleep 8

echo "Testing Phase 1 performance..."
START_TIME=$(date +%s.%N)
for i in {1..200}; do
    printf "*3\r\n\$3\r\nSET\r\n\$11\r\nphase1:key$i\r\n\$12\r\nphase1:val$i\r\n" | nc -w 1 127.0.0.1 6379 > /dev/null 2>&1
done
END_TIME=$(date +%s.%N)
PHASE1_TIME=$(echo "$END_TIME - $START_TIME" | bc -l)

echo "✅ Phase 1: 200 commands in ${PHASE1_TIME}s"  
echo "✅ Phase 1 QPS: $(echo "scale=0; 200 / $PHASE1_TIME" | bc -l)"

# Test correctness  
echo "Testing Phase 1 correctness..."
printf "*3\r\n\$3\r\nSET\r\n\$13\r\ncorrect:phase1\r\n\$10\r\noptimized\r\n" | nc -w 2 127.0.0.1 6379
printf "*2\r\n\$3\r\nGET\r\n\$13\r\ncorrect:phase1\r\n" | nc -w 2 127.0.0.1 6379

# Performance improvement
IMPROVEMENT=$(echo "scale=2; $BASELINE_TIME / $PHASE1_TIME" | bc -l)
echo ""
echo "=== PERFORMANCE ANALYSIS ==="
echo "📊 Baseline time: ${BASELINE_TIME}s"
echo "📊 Phase 1 time: ${PHASE1_TIME}s" 
echo "📊 Performance improvement: ${IMPROVEMENT}x"

if (( $(echo "$IMPROVEMENT > 1.5" | bc -l) )); then
    echo "🚀 SUCCESS: Phase 1 achieved significant performance improvement!"
else
    echo "⚠️  Phase 1 improvement lower than expected. Need further optimization."
fi

kill $PHASE1_PID 2>/dev/null || true
echo ""
echo "$(date): Benchmark complete"












