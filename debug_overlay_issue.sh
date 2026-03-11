#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TTL OVERLAY vs BASELINE DIAGNOSTIC ==="
echo "$(date): Comparing TTL overlay with working baseline"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== BASELINE VERIFICATION (should work perfectly) ==="
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_verify.log 2>&1 &
BASE_PID=$!
sleep 6

echo -n "Baseline SET: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasetest\r\n\$9\r\nbaseval\r\n" | nc -w 3 127.0.0.1 6379

echo -n "Baseline GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasetest\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

kill $BASE_PID 2>/dev/null || true
sleep 3

echo ""
echo "=== TTL OVERLAY DIAGNOSTIC (should match baseline) ==="
nohup ./meteor_ttl_overlay -c 4 -s 4 > overlay_diag.log 2>&1 &
OVERLAY_PID=$!
sleep 8

echo -n "Overlay SET: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\noverlaytest\r\n\$11\r\noverlayval\r\n" | nc -w 3 127.0.0.1 6379

echo -n "Overlay GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\noverlaytest\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "=== SERVER LOG ANALYSIS ==="
echo "Last 10 lines of overlay server log:"
tail -10 overlay_diag.log

kill $OVERLAY_PID 2>/dev/null || true

echo ""
echo "=== DIAGNOSTIC CONCLUSION ==="
echo "🔍 If baseline works but overlay fails:"
echo "  → Our TTL overlay changes broke core functionality"
echo "  → Need to identify what modification caused regression"
echo ""
echo "🔍 If both fail:"
echo "  → Environment or compilation issue"
echo ""
echo "🔍 Expected results:"
echo "  → Baseline: SET +OK, GET returns actual value"
echo "  → Overlay: Should match baseline exactly"
echo ""
echo "$(date): TTL overlay diagnostic complete"












