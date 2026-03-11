#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== COMPARISON: WORKING BASELINE VS OPTIMIZED ==="
echo "$(date): Comparing baseline vs optimized version"

pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== TESTING WORKING BASELINE ==="
echo "Starting working baseline server..."
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_test.log 2>&1 &
BASELINE_PID=$!
echo "Baseline server PID: $BASELINE_PID"
sleep 6

echo "Baseline tests:"
echo -n "SET testkey: "
printf "*3\r\n\$3\r\nSET\r\n\$7\r\ntestkey\r\n\$8\r\ntestval1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET testkey: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntestkey\r\n" | nc -w 3 127.0.0.1 6379

kill $BASELINE_PID 2>/dev/null || true
sleep 3

echo ""
echo "=== TESTING OPTIMIZED VERSION ==="
echo "Starting optimized server..."
nohup ./cpp/meteor_phase1_fully_fixed -c 4 -s 4 > optimized_test.log 2>&1 &
OPT_PID=$!
echo "Optimized server PID: $OPT_PID"
sleep 6

echo "Optimized tests:"
echo -n "SET testkey: "
printf "*3\r\n\$3\r\nSET\r\n\$7\r\ntestkey\r\n\$8\r\ntestval2\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET testkey: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntestkey\r\n" | nc -w 3 127.0.0.1 6379

kill $OPT_PID 2>/dev/null || true

echo ""
echo "=== ANALYSIS ==="
echo "BASELINE: Should show SET +OK and GET with actual value"
echo "OPTIMIZED: If broken, will show SET +OK but GET empty/wrong"
echo ""
echo "If baseline works but optimized doesn't, there's a core routing or cache issue"
echo ""
echo "$(date): Comparison test complete"












