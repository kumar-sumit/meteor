#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TESTING UNIFIED APPROACH ==="
echo "$(date): Testing unified version (single commands as single-item pipelines)"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== BASELINE VS UNIFIED COMPARISON ==="

echo "--- Testing BASELINE (dual code paths) ---"
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_unified_test.log 2>&1 &
BASELINE_PID=$!
echo "Baseline server PID: $BASELINE_PID"
sleep 6

echo "Baseline sequential GET test:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasekey1\r\n\$9\r\nbaseval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET 1: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "GET 2: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "GET 3: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

kill $BASELINE_PID 2>/dev/null || true
sleep 3

echo ""
echo "--- Testing UNIFIED (single code path) ---"
nohup ./cpp/meteor_unified -c 4 -s 4 > unified_test.log 2>&1 &
UNIFIED_PID=$!
echo "Unified server PID: $UNIFIED_PID"
sleep 6

echo "Unified sequential GET test:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nunifkey1\r\n\$9\r\nunifval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET 1: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nunifkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "GET 2: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nunifkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "GET 3: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nunifkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "Unified cross-core test:"
echo -n "Cross SET: "
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscorekey\r\n\$13\r\ncrosscore999\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Cross GET 1: "
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorekey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "Cross GET 2: "
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorekey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

kill $UNIFIED_PID 2>/dev/null || true

echo ""
echo "=== UNIFIED APPROACH RESULTS ==="
echo "Expected if unified approach works:"
echo "✅ All GET commands return proper values (no hanging)"
echo "✅ Cross-core commands work correctly"
echo "✅ Sequential GETs continue working (no blocking after first GET)"
echo "✅ Same correctness as baseline but with unified processing"
echo ""
echo "$(date): Unified approach test complete"












