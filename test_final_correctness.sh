#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== FINAL CORRECTNESS VALIDATION AFTER ROUTING FIX ==="
echo "$(date): Testing corrected routing logic"

# Kill any running servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== CORRECTED BASELINE SERVER TEST ==="
echo "Starting corrected baseline server..."
nohup ./cpp/meteor_single_command_fixed_corrected -c 4 -s 4 > baseline_corrected.log 2>&1 &
BASELINE_PID=$!
echo "Baseline server PID: $BASELINE_PID"
sleep 8

echo "Testing corrected baseline SET/GET:"
echo -n "SET key1: "
printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey1\r\n\$6\r\nvalue1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET key1: "
printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey1\r\n" | nc -w 3 127.0.0.1 6379

echo -n "SET crosscorekey: "
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscorekey\r\n\$13\r\ncrosscoretest\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET crosscorekey: "
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorekey\r\n" | nc -w 3 127.0.0.1 6379

kill $BASELINE_PID 2>/dev/null || true
sleep 3

echo ""
echo "=== CORRECTED OPTIMIZED SERVER TEST ==="
echo "Starting corrected optimized server..."
nohup ./cpp/meteor_single_command_optimized_v1_final -c 4 -s 4 > optimized_corrected.log 2>&1 &
OPTIMIZED_PID=$!
echo "Optimized server PID: $OPTIMIZED_PID"
sleep 8

echo "Testing corrected optimized SET/GET:"
echo -n "SET key2: "
printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey2\r\n\$6\r\nvalue2\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET key2: "
printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey2\r\n" | nc -w 3 127.0.0.1 6379

echo -n "SET crosskey: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ncrosskey\r\n\$9\r\ncrossval\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET crosskey: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\ncrosskey\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "=== VALIDATION RESULTS ==="
echo "Expected:"
echo "- SET commands should return +OK"
echo "- GET commands should return the actual values (not \$-1 or nil)"
echo "- No commands should hang"

kill $OPTIMIZED_PID 2>/dev/null || true

echo ""
echo "$(date): Correctness validation complete"












