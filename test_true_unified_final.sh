#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TRUE UNIFIED APPROACH TEST ==="
echo "$(date): Testing true unified version (single commands → pipeline processing)"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== DECISIVE TEST: BASELINE vs TRUE UNIFIED ==="

echo "--- BASELINE (reference) ---"
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_ref.log 2>&1 &
BASE_PID=$!
sleep 6
printf "*3\r\n\$3\r\nSET\r\n\$7\r\nrefkey1\r\n\$8\r\nrefval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Baseline GET: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nrefkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
kill $BASE_PID 2>/dev/null || true

sleep 3

echo ""
echo "--- TRUE UNIFIED (single commands through pipeline function) ---"
nohup ./cpp/meteor_true_unified -c 4 -s 4 > true_unified.log 2>&1 &
TRUE_PID=$!
sleep 6
printf "*3\r\n\$3\r\nSET\r\n\$7\r\ntrukey1\r\n\$8\r\ntruval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "True Unified GET: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntrukey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "Sequential GET test (check for hanging):"
echo -n "GET 2: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntrukey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "GET 3: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntrukey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "Cross-core test:"
echo -n "Cross SET: "
printf "*3\r\n\$3\r\nSET\r\n\$9\r\ncrosskey1\r\n\$10\r\ncrossval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Cross GET: "
printf "*2\r\n\$3\r\nGET\r\n\$9\r\ncrosskey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

kill $TRUE_PID 2>/dev/null || true

echo ""
echo "=== FINAL VERDICT ==="
echo "🎯 SUCCESS IF:"
echo "  ✅ True Unified GET returns same format as Baseline"
echo "  ✅ No hanging on subsequent GET commands" 
echo "  ✅ Cross-core commands work correctly"
echo "  ✅ Single commands now use proven pipeline processing"
echo ""
echo "🚀 If this works, we've successfully:"
echo "  🏆 Implemented your unified architecture insight"
echo "  🏆 Eliminated problematic dual code paths"
echo "  🏆 Created foundation for cross-core performance optimizations"
echo ""
echo "$(date): True unified approach test complete"












