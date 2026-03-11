#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== FIXED UNIFIED APPROACH - FINAL TEST ==="
echo "$(date): Testing unified approach with pipeline routing + proven data storage"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== COMPREHENSIVE FINAL VALIDATION ==="

echo "Starting fixed unified server..."
nohup ./cpp/meteor_true_pipeline_unified -c 4 -s 4 > fixed_unified.log 2>&1 &
FIXED_PID=$!
sleep 8

echo "✅ SINGLE COMMAND TESTS (should now work with data storage)"
echo "Test 1: Single SET + Single GET"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nfixedkey1\r\n\$10\r\nfixedval1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "Single GET: "
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nfixedkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "Test 2: Multiple single operations"
for i in {1..5}; do
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nfixed$i\r\n\$9\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
done
echo "Retrieve all:"
for i in {1..5}; do
    echo -n "GET fixed$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nfixed$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "✅ PIPELINE COMMAND TESTS (should continue to work)"
echo "Test 3: Pipeline SET+GET"
{
printf "*3\r\n\$3\r\nSET\r\n\$9\r\npipekey1\r\n\$10\r\npipeval1\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$9\r\npipekey1\r\n"
} | nc -w 3 127.0.0.1 6379

echo ""
echo "Test 4: Multiple pipeline operations"
for i in {1..3}; do
    echo "Pipeline $i:"
    {
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\npipe$i\r\n\$9\r\nvalue$i\r\n"
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\npipe$i\r\n"
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\npipe$i\r\n"
    } | nc -w 3 127.0.0.1 6379
done

echo ""
echo "✅ MIXED OPERATIONS TEST"
echo "Test 5: Cross-verification (SET as single, GET as pipeline)"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ncrosskey\r\n\$9\r\ncrossval\r\n" | nc -w 2 127.0.0.1 6379
echo "Pipeline GET:"
{
printf "*2\r\n\$3\r\nGET\r\n\$8\r\ncrosskey\r\n"
} | nc -w 3 127.0.0.1 6379

echo ""
echo "Test 6: Concurrent connections"
for i in {1..4}; do
    {
        printf "*3\r\n\$3\r\nSET\r\n\$6\r\nconc$i\r\n\$7\r\nval$i\r\n" | nc -w 2 127.0.0.1 6379
        printf "*2\r\n\$3\r\nGET\r\n\$6\r\nconc$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
    } &
done
wait

echo ""
echo "✅ CROSS-SHARD ROUTING TEST"
echo "Test 7: Different keys (should route to different cores/shards)"
keys=("shard1" "shard2" "shard3" "shard4")
for key in "${keys[@]}"; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\n$key\r\n\$8\r\nshardval\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET $key: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\n$key\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

kill $FIXED_PID 2>/dev/null || true

echo ""
echo "=== FIXED UNIFIED APPROACH VERDICT ==="
echo "🏆 COMPLETE SUCCESS IF:"
echo "  ✅ Single commands: SET +OK, GET returns actual data (not $-1)"
echo "  ✅ Pipeline commands: Both SET+GET work in same connection"
echo "  ✅ Cross-verification: Single SET + Pipeline GET works"
echo "  ✅ Concurrent operations: Multiple connections work simultaneously"
echo "  ✅ Cross-shard routing: Different keys route properly and return data"
echo ""
echo "🚀 IF SUCCESSFUL - WE HAVE ACHIEVED:"
echo "  🎯 TRUE UNIFIED APPROACH: One code path for single + pipeline"
echo "  🎯 PROVEN PIPELINE ROUTING: Cross-core coordination working"
echo "  🎯 PROVEN DATA STORAGE: submit_operation() mechanism preserved"
echo "  🎯 NO HANGING ISSUES: All operations complete successfully"
echo "  🎯 READY FOR 5x OPTIMIZATIONS: Solid foundation established"
echo ""
echo "$(date): Fixed unified approach test complete"












