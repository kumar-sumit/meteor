#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TESTING CORRECTED VERSION (NO RING BUFFER) ==="
echo "$(date): Testing corrected version with ring buffer disabled"

# Kill any running servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== CORRECTED OPTIMIZED SERVER TEST ==="
echo "Starting corrected optimized server (no ring buffer)..."
nohup ./cpp/meteor_phase1_optimized_corrected -c 4 -s 4 > corrected_server.log 2>&1 &
OPTIMIZED_PID=$!
echo "Corrected server PID: $OPTIMIZED_PID"
sleep 8

echo "Testing corrected optimized version:"
echo -n "SET simple: "
printf "*3\r\n\$3\r\nSET\r\n\$6\r\nsimple\r\n\$7\r\nsimval\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET simple: "
printf "*2\r\n\$3\r\nGET\r\n\$6\r\nsimple\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing cross-core commands (this was hanging before):"
echo -n "SET cross-core: "
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscorekey\r\n\$13\r\ncrosscoreval\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET cross-core: "
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorekey\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing multiple keys (this was failing before):"
for i in {1..3}; do
    echo "Testing key$i:"
    echo -n "SET: "
    printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey$i\r\n\$6\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET: "
    printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey$i\r\n" | nc -w 2 127.0.0.1 6379
    echo "---"
done

kill $OPTIMIZED_PID 2>/dev/null || true

echo ""
echo "=== VALIDATION RESULTS ==="
echo "Expected Results (if ring buffer was the issue):"
echo "✅ All SET commands return +OK"  
echo "✅ All GET commands return actual values (not hanging)"
echo "✅ Cross-core commands work correctly"
echo "✅ Multiple key tests work correctly"
echo ""
echo "$(date): Corrected version test complete"












