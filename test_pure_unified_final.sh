#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== PURE PIPELINE UNIFIED - FINAL TEST ==="
echo "$(date): Testing pure unified approach using unmodified proven pipeline processing"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== PURE UNIFIED VALIDATION ==="

echo "Starting pure pipeline unified server..."
nohup ./cpp/meteor_pure_pipeline_unified -c 4 -s 4 > pure_unified.log 2>&1 &
PURE_PID=$!
sleep 8

echo ""
echo "🔥 PURE APPROACH TEST - Should work exactly like baseline pipeline"

echo "✅ Single operations (treated as pipeline of 1):"
for i in {1..5}; do
    echo "Pure single $i:"
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\npure$i\r\n\$7\r\nval$i\r\n" | timeout 5s nc -w 5 127.0.0.1 6379
    echo -n "  GET: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\npure$i\r\n" | timeout 5s nc -w 5 127.0.0.1 6379
    echo ""
done

echo ""
echo "✅ Pipeline operations (should work as always):"
for i in {1..3}; do
    echo "Pipeline $i:"
    {
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\npipe$i\r\n\$9\r\nvalue$i\r\n"
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\npipe$i\r\n"
    } | timeout 5s nc -w 5 127.0.0.1 6379
    echo ""
done

echo ""
echo "✅ Mixed single and pipeline:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nmixedkey\r\n\$9\r\nmixedval\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
{
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nmixedkey\r\n"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nmixedkey2\r\n\$10\r\nmixedval2\r\n"
} | timeout 5s nc -w 5 127.0.0.1 6379

echo ""
echo "✅ Same connection multiple operations:"
{
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nsameconn\r\n\$9\r\nconnval\r\n"
    sleep 0.1
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nsameconn\r\n"
    sleep 0.1
    printf "*3\r\n\$3\r\nSET\r\n\$9\r\nsameconn2\r\n\$10\r\nconnval2\r\n"
    sleep 0.1
    printf "*2\r\n\$3\r\nGET\r\n\$9\r\nsameconn2\r\n"
} | timeout 10s nc -w 10 127.0.0.1 6379

kill $PURE_PID 2>/dev/null || true

echo ""
echo "=== COMPARISON WITH BASELINE ==="
echo "Running same tests on baseline for verification..."

nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_comparison.log 2>&1 &
BASE_PID=$!
sleep 6

echo "Baseline single operations:"
for i in {1..3}; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nbase$i\r\n\$7\r\nval$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "Baseline GET $i: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nbase$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "Baseline pipeline:"
{
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasepipe\r\n\$9\r\nbaseval\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasepipe\r\n"
} | nc -w 3 127.0.0.1 6379

kill $BASE_PID 2>/dev/null || true

echo ""
echo "=== PURE UNIFIED VERDICT ==="
echo "🏆 PURE APPROACH SUCCESS IF:"
echo "  ✅ Pure unified matches baseline behavior exactly"
echo "  ✅ Single operations work without any hanging"
echo "  ✅ Pipeline operations work identically to baseline"
echo "  ✅ Same connection operations complete successfully"
echo "  ✅ No server blocking or connection issues"
echo ""
echo "🚀 IF SUCCESSFUL - PURE UNIFIED APPROACH ACHIEVED:"
echo "  🎯 ZERO MODIFICATIONS to proven pipeline processing"
echo "  🎯 TRUE UNIFIED ARCHITECTURE via pipeline routing"
echo "  🎯 IDENTICAL BEHAVIOR to working baseline"
echo "  🎯 READY FOR 5x PERFORMANCE OPTIMIZATIONS"
echo ""
echo "$(date): Pure pipeline unified test complete"












