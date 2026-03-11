#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== FINAL TEST: MINIMAL UNIFIED APPROACH ==="
echo "$(date): Testing minimal unified version (eliminates dual code paths)"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== SIDE-BY-SIDE COMPARISON ==="

echo "--- BASELINE (known working) ---"
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_final.log 2>&1 &
BASE_PID=$!
sleep 6
echo "Baseline tests:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasekey1\r\n\$9\r\nbaseval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Baseline GET 1: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "Baseline GET 2: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
kill $BASE_PID 2>/dev/null || true

sleep 3

echo ""
echo "--- MINIMAL UNIFIED (should match baseline) ---"
nohup ./cpp/meteor_minimal_unified -c 4 -s 4 > minimal_unified.log 2>&1 &
MIN_PID=$!
sleep 6
echo "Minimal unified tests:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nminkey1\r\n\$9\r\nminval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Minimal GET 1: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nminkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "Minimal GET 2: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nminkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "Minimal GET 3: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nminkey1\r\n" | timeout 3s nc -w 3 127 0.0.1 6379

echo ""
echo "Stress test (multiple rapid commands):"
for i in {1..5}; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\ntest$i\r\n\$5\r\nval$i\r\n" | nc -w 1 127.0.0.1 6379 >/dev/null &
done
wait
sleep 1
for i in {1..5}; do
    echo -n "GET test$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\ntest$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

kill $MIN_PID 2>/dev/null || true

echo ""
echo "=== FINAL RESULTS ==="
echo "🎯 SUCCESS CRITERIA:"
echo "  ✅ Minimal unified GET responses should match baseline format"
echo "  ✅ No hanging or timeout issues"  
echo "  ✅ Multiple sequential commands should work"
echo "  ✅ Both single and pipeline logic unified"
echo ""
echo "If this works, we have successfully:"
echo "  🚀 Eliminated the dual code path complexity"
echo "  🚀 Fixed the hanging issue with unified processing"
echo "  🚀 Created a solid foundation for cross-core optimizations"
echo ""
echo "$(date): Minimal unified final test complete"












