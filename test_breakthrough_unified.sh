#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== BREAKTHROUGH UNIFIED APPROACH TEST ==="
echo "$(date): Testing truly unified approach with direct cache operations"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== FINAL BREAKTHROUGH VALIDATION ==="

echo "Starting breakthrough unified server..."
nohup ./cpp/meteor_true_pipeline_unified -c 4 -s 4 > breakthrough.log 2>&1 &
BREAK_PID=$!
sleep 8

echo ""
echo "🎯 SINGLE OPERATIONS (should work without blocking)"
for i in {1..5}; do
    echo "Operation $i:"
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbreach$i\r\n\$9\r\nvalue$i\r\n" | nc -w 3 127.0.0.1 6379
    echo -n "  GET: "
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbreach$i\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
done

echo ""
echo "🎯 SAME CONNECTION TEST (should not hang)"
echo "Multiple operations same connection:"
{
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nsameconn\r\n\$9\r\nconnval\r\n"
    sleep 0.2
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nsameconn\r\n"
    sleep 0.2
    printf "*3\r\n\$3\r\nSET\r\n\$9\r\nsameconn2\r\n\$10\r\nconnval2\r\n"
    sleep 0.2
    printf "*2\r\n\$3\r\nGET\r\n\$9\r\nsameconn2\r\n"
} | timeout 10s nc -w 10 127.0.0.1 6379

echo ""
echo "🎯 PIPELINE OPERATIONS (should work as before)"
for i in {1..3}; do
    echo "Pipeline $i:"
    {
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\npipe$i\r\n\$9\r\nvalue$i\r\n"
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\npipe$i\r\n"
    } | timeout 5s nc -w 5 127.0.0.1 6379
done

echo ""
echo "🎯 CONCURRENT CONNECTIONS (should all complete)"
for i in {1..4}; do
    {
        echo "Concurrent $i:"
        printf "*3\r\n\$3\r\nSET\r\n\$6\r\nconc$i\r\n\$7\r\nval$i\r\n" | nc -w 3 127.0.0.1 6379
        printf "*2\r\n\$3\r\nGET\r\n\$6\r\nconc$i\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
    } &
done
wait
echo "All concurrent operations completed!"

echo ""
echo "🎯 CROSS-SHARD TEST (different cores/shards)"
keys=("alpha" "beta" "gamma" "delta")
for key in "${keys[@]}"; do
    printf "*3\r\n\$3\r\nSET\r\n\$5\r\n$key\r\n\$8\r\nshardval\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "$key: "
    printf "*2\r\n\$3\r\nGET\r\n\$5\r\n$key\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
done

kill $BREAK_PID 2>/dev/null || true

echo ""
echo "=== BREAKTHROUGH VERDICT ==="
echo "🏆 UNIFIED APPROACH SUCCESS IF:"
echo "  ✅ All single operations work (no hanging after first)"
echo "  ✅ Same connection works (multiple operations in sequence)"
echo "  ✅ Pipeline operations work (proven mechanism unchanged)"
echo "  ✅ Concurrent connections all complete successfully"
echo "  ✅ Cross-shard operations route and return data correctly"
echo ""
echo "🚀 IF ALL PASS - WE HAVE ACHIEVED:"
echo "  🎯 TRUE UNIFIED ARCHITECTURE: Single code path for all operations"
echo "  🎯 NO SERVER BLOCKING: Consistent connection handling"
echo "  🎯 PROVEN DATA STORAGE: Direct cache operations ensure persistence"
echo "  🎯 PROVEN CROSS-CORE ROUTING: Boost fiber coordination intact"
echo "  🎯 READY FOR 5x PERFORMANCE OPTIMIZATIONS: Solid unified foundation"
echo ""
echo "$(date): Breakthrough unified approach test complete"












