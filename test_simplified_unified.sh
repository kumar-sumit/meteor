#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TESTING SIMPLIFIED UNIFIED APPROACH ==="
echo "$(date): Testing simplified unified version (all local processing)"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== CORRECTNESS TEST ==="
echo "Starting simplified unified server..."
nohup ./cpp/meteor_unified_simplified -c 4 -s 4 > simplified_unified.log 2>&1 &
UNIFIED_PID=$!
echo "Unified server PID: $UNIFIED_PID"
sleep 8

echo "Basic functionality test:"
echo -n "SET: "
printf "*3\r\n\$3\r\nSET\r\n\$7\r\ntestkey\r\n\$8\r\ntestval\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET 1: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntestkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "GET 2: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntestkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
echo -n "GET 3: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntestkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "Multiple keys test:"
for i in {1..3}; do
    echo -n "SET key$i: "
    printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey$i\r\n\$6\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET key$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "Pipeline test (should work same as single commands):"
echo -n "Pipeline SET+GET: "
{
printf "*3\r\n\$3\r\nSET\r\n\$8\r\npipekey1\r\n\$9\r\npipeval1\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$8\r\npipekey1\r\n"
} | nc -w 3 127.0.0.1 6379

kill $UNIFIED_PID 2>/dev/null || true

echo ""
echo "=== EXPECTED RESULTS ==="
echo "✅ All SET commands return +OK"
echo "✅ All GET commands return proper values (not \$-1)"
echo "✅ No hanging or timeout issues" 
echo "✅ Multiple sequential GETs work correctly"
echo "✅ Both single and pipeline commands work identically"
echo ""
echo "If this works, we have a correct unified baseline to optimize!"
echo ""
echo "$(date): Simplified unified test complete"












