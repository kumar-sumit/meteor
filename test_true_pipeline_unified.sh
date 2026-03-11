#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TRUE PIPELINE UNIFIED APPROACH TEST ==="
echo "$(date): Testing version that uses proven pipeline infrastructure for ALL commands"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== COMPREHENSIVE VALIDATION ==="

echo "--- BASELINE (reference standard) ---"
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_pipeline.log 2>&1 &
BASE_PID=$!
sleep 6

echo "Baseline single command:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasekey1\r\n\$9\r\nbaseval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Baseline GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo "Baseline pipeline:"
{
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasepipe\r\n\$9\r\nbaseval2\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasepipe\r\n"
} | nc -w 3 127.0.0.1 6379

kill $BASE_PID 2>/dev/null || true
sleep 3

echo ""
echo "--- TRUE PIPELINE UNIFIED (should match baseline exactly) ---"
nohup ./cpp/meteor_true_pipeline_unified -c 4 -s 4 > true_pipeline.log 2>&1 &
UNIFIED_PID=$!
sleep 8

echo "Unified single command:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nunifkey1\r\n\$9\r\nunifval1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "Unified GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nunifkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo "Unified pipeline:"
{
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nunifpipe\r\n\$9\r\nunifval2\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nunifpipe\r\n"
} | nc -w 3 127.0.0.1 6379

echo ""
echo "Sequential operations test:"
for i in {1..5}; do
    echo -n "GET $i: "
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nunifkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "Cross-shard coordination test:"
for i in {1..3}; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nshard$i\r\n\$7\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET shard$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nshard$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "Concurrent connections test:"
for i in {1..3}; do
    {
        printf "*3\r\n\$3\r\nSET\r\n\$6\r\nconc$i\r\n\$7\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
        printf "*2\r\n\$3\r\nGET\r\n\$6\r\nconc$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
    } &
done
wait

kill $UNIFIED_PID 2>/dev/null || true

echo ""
echo "=== TRUE PIPELINE UNIFIED VERDICT ==="
echo "🎯 COMPLETE SUCCESS IF:"
echo "  ✅ All unified commands return same results as baseline"
echo "  ✅ Single commands work identically to pipeline commands" 
echo "  ✅ No hanging, timeout, or empty response issues"
echo "  ✅ Cross-shard coordination works via boost fibers"
echo "  ✅ Concurrent operations complete successfully"
echo ""
echo "🏆 UNIFIED APPROACH USING PROVEN INFRASTRUCTURE:"
echo "  🚀 Single code path through working pipeline processing"
echo "  🚀 Cross-shard coordination via proven message passing"
echo "  🚀 ResponseTracker maintains command ordering"
echo "  🚀 Boost fiber future.get() for cross-core responses"
echo "  🚀 Ready for 5x performance optimizations"
echo ""
echo "$(date): True pipeline unified test complete"












