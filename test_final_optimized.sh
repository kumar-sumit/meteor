#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TESTING FINAL OPTIMIZED VERSION ==="
echo "$(date): Testing fully optimized version with ring buffer enabled"

pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== FINAL OPTIMIZED SERVER TEST ==="
echo "Starting final optimized server with ring buffer..."
nohup ./cpp/meteor_phase1_final_optimized -c 4 -s 4 > final_optimized.log 2>&1 &
FINAL_PID=$!
echo "Final optimized server PID: $FINAL_PID"
sleep 8

echo "Testing final optimized version:"
echo -n "SET simple: "
printf "*3\r\n\$3\r\nSET\r\n\$6\r\nsimple\r\n\$10\r\nsimplevalue\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET simple: "
printf "*2\r\n\$3\r\nGET\r\n\$6\r\nsimple\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing cross-core commands with ring buffer:"
echo -n "SET cross-core: "
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscorekey\r\n\$13\r\ncrosscore123\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET cross-core: "
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorekey\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing multiple keys with ring buffer optimizations:"
for i in {1..3}; do
    echo "Testing optkey$i:"
    echo -n "SET: "
    printf "*3\r\n\$3\r\nSET\r\n\$7\r\noptkey$i\r\n\$9\r\noptvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET: "
    printf "*2\r\n\$3\r\nGET\r\n\$7\r\noptkey$i\r\n" | nc -w 2 127.0.0.1 6379
    echo "---"
done

echo ""
echo "Testing rapid fire commands (ring buffer stress test):"
for i in {1..5}; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nfast$i\r\n\$5\r\nval$i\r\n" | nc -w 1 127.0.0.1 6379 &
done
wait
sleep 2
for i in {1..5}; do
    echo -n "GET fast$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nfast$i\r\n" | nc -w 1 127.0.0.1 6379
done

kill $FINAL_PID 2>/dev/null || true

echo ""
echo "=== RING BUFFER OPTIMIZATION RESULTS ==="
echo "✅ Expected: All commands work correctly with ring buffer optimizations"
echo "✅ Expected: No hanging, proper responses, cross-core commands work"  
echo "✅ Expected: Performance improvement due to zero-copy ring buffer"
echo ""
echo "$(date): Final optimized version test complete"












