#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== CACHE CONSISTENCY FIX TEST ==="
echo "$(date): Testing consistent unified version with fixed core-based routing"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== DEFINITIVE CONSISTENCY TEST ==="

echo "--- BASELINE (reference) ---"
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_consistency.log 2>&1 &
BASE_PID=$!
sleep 6
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nconskey1\r\n\$9\r\nconsval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Baseline GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nconskey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
kill $BASE_PID 2>/dev/null || true

sleep 3

echo ""
echo "--- CONSISTENT UNIFIED (cache consistency fix) ---"
nohup ./cpp/meteor_consistent_unified -c 4 -s 4 > consistent_unified.log 2>&1 &
CONS_PID=$!
sleep 6
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nfixkey1\r\n\$9\r\nfixval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Consistent GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nfixkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "Sequential operations test (check for hanging):"
for i in {1..3}; do
    echo -n "SET key$i: "
    printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey$i\r\n\$6\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET key$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
    echo "---"
done

echo ""
echo "Performance stress test:"
echo "Rapid fire commands (should all complete):"
for i in {1..5}; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nperf$i\r\n\$5\r\nval$i\r\n" | nc -w 1 127.0.0.1 6379 &
done
wait
sleep 1
for i in {1..5}; do
    echo -n "GET perf$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nperf$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

kill $CONS_PID 2>/dev/null || true

echo ""
echo "=== BREAKTHROUGH VERIFICATION ==="
echo "🎯 SUCCESS CRITERIA:"
echo "  ✅ Consistent GET should return actual values (not \$-1)"  
echo "  ✅ Format should match baseline: \$N<CRLF>value<CRLF>"
echo "  ✅ No hanging or timeout issues"
echo "  ✅ All SET/GET pairs should work correctly"
echo ""
echo "🚀 If this works, we've achieved:"
echo "  🏆 Your unified architecture insight implemented correctly"
echo "  🏆 Eliminated dual code paths and hanging issues"
echo "  🏆 Fixed cache consistency with proper core routing"
echo "  🏆 Created foundation for cross-core performance optimizations"
echo ""
echo "$(date): Consistency fix test complete"












