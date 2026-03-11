#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== COMPREHENSIVE CORRECTNESS TEST ==="
echo "$(date): Starting correctness validation"

# Kill any running servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== BASELINE SERVER CORRECTNESS TEST ==="
echo "Starting baseline server..."
nohup ./cpp/meteor_single_command_fixed -c 4 -s 4 > baseline_test.log 2>&1 &
BASELINE_PID=$!
echo "Baseline server PID: $BASELINE_PID"
sleep 8

echo "Testing baseline SET/GET:"
echo "SET test1:"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nbaseline1\r\n\$10\r\nbasevalue1\r\n" | nc -w 3 127.0.0.1 6379
echo "GET test1:"
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nbaseline1\r\n" | nc -w 3 127.0.0.1 6379

echo "Cross-core test:"
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscorebase\r\n\$13\r\ncrosscorebase\r\n" | nc -w 3 127.0.0.1 6379
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorebase\r\n" | nc -w 3 127.0.0.1 6379

kill $BASELINE_PID 2>/dev/null || true
sleep 3

echo ""
echo "=== OPTIMIZED SERVER CORRECTNESS TEST ==="
echo "Starting optimized server..."
nohup ./cpp/meteor_single_command_optimized_v1_corrected -c 4 -s 4 > optimized_test.log 2>&1 &
OPTIMIZED_PID=$!
echo "Optimized server PID: $OPTIMIZED_PID"
sleep 8

echo "Testing optimized SET/GET:"
echo "SET test1:"
printf "*3\r\n\$3\r\nSET\r\n\$10\r\noptimized1\r\n\$11\r\noptvalue1\r\n" | nc -w 3 127.0.0.1 6379
echo "GET test1:"
printf "*2\r\n\$3\r\nGET\r\n\$10\r\noptimized1\r\n" | nc -w 3 127.0.0.1 6379

echo "Cross-core test:"
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscoreopt\r\n\$13\r\ncrosscoreopt\r\n" | nc -w 3 127.0.0.1 6379
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscoreopt\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "=== MULTIPLE KEY TEST ==="
for i in {1..5}; do
    echo "Testing key$i:"
    printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey$i\r\n\$6\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey$i\r\n" | nc -w 2 127.0.0.1 6379
    echo "---"
done

kill $OPTIMIZED_PID 2>/dev/null || true

echo ""
echo "=== TEST SUMMARY ==="
echo "$(date): Correctness test complete"
echo "Check the output above to verify:"
echo "1. SET commands return +OK"
echo "2. GET commands return the stored values"
echo "3. No commands hang or return nil"












