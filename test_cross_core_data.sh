#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== CROSS-CORE DATA DIAGNOSTIC ==="
echo "$(date): Testing if data is isolated per core"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== DATA ISOLATION TEST ==="

echo "--- Testing Unified Version Data Access Patterns ---"
nohup ./cpp/meteor_direct_unified -c 4 -s 4 > data_test.log 2>&1 &
UNIFIED_PID=$!
sleep 6

echo "Data access pattern analysis:"
echo "Setting multiple keys to see access patterns:"

for i in {1..5}; do
    echo -n "SET key$i: "
    printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey$i\r\n\$6\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
done

sleep 1
echo ""
echo "Getting same keys immediately after SET:"

for i in {1..5}; do
    echo -n "GET key$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "Testing with different key hash distributions:"
# Test keys that likely map to different cores
echo -n "SET aaaaa: "
printf "*3\r\n\$3\r\nSET\r\n\$5\r\naaaaa\r\n\$6\r\nval_a\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET aaaaa: "
printf "*2\r\n\$3\r\nGET\r\n\$5\r\naaaaa\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "SET zzzzz: "
printf "*3\r\n\$3\r\nSET\r\n\$5\r\nzzzzz\r\n\$6\r\nval_z\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET zzzzz: "
printf "*2\r\n\$3\r\nGET\r\n\$5\r\nzzzzz\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "SET 12345: "
printf "*3\r\n\$3\r\nSET\r\n\$5\r\n12345\r\n\$6\r\nval_n\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET 12345: "
printf "*2\r\n\$3\r\nGET\r\n\$5\r\n12345\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

kill $UNIFIED_PID 2>/dev/null || true

echo ""
echo "=== DIAGNOSTIC ANALYSIS ==="
echo "🔍 If ALL GETs return \$-1:"
echo "  → Data is not being stored or accessible"
echo "  → Cache instances might be per-core isolated"
echo "  → Need cross-core data synchronization"
echo ""
echo "🔍 If SOME GETs work and others don't:"
echo "  → Hash-based core partitioning is working"
echo "  → Need to implement proper key→core routing"
echo ""
echo "🔍 If NO GETs work despite immediate SET:"
echo "  → Cache access issue in unified processing"
echo "  → Need to debug submit_operation implementation"
echo ""
echo "$(date): Cross-core data diagnostic complete"












