#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== DEEP DIVE ROOT CAUSE ANALYSIS ==="
echo "$(date): Investigating why most GET commands fail in unified approach"

pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== CONTROLLED SINGLE OPERATION TEST ==="

echo "Starting unified server with detailed timing..."
nohup ./cpp/meteor_correct_unified -c 4 -s 4 > deep_dive.log 2>&1 &
UNIFIED_PID=$!
sleep 8

echo "Test 1: Single SET then immediate GET (same connection)"
printf "*3\r\n\$3\r\nSET\r\n\$5\r\ntest1\r\n\$6\r\nvalue1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "Immediate GET: "
printf "*2\r\n\$3\r\nGET\r\n\$5\r\ntest1\r\n" | timeout 5s nc -w 5 127.0.0.1 6379

echo ""
echo "Test 2: SET+GET in same connection"
{
printf "*3\r\n\$3\r\nSET\r\n\$5\r\ntest2\r\n\$6\r\nvalue2\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$5\r\ntest2\r\n"
} | nc -w 5 127.0.0.1 6379

echo ""
echo "Test 3: Multiple separate connections"
for i in {1..3}; do
    echo "Connection $i:"
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nconn$i\r\n\$7\r\nvalue$i\r\n" | nc -w 3 127.0.0.1 6379 &
done
wait
sleep 2
for i in {1..3}; do
    echo -n "GET conn$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nconn$i\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
done

echo ""
echo "Test 4: Server responsiveness check"
echo -n "PING test: "
printf "PING\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

kill $UNIFIED_PID 2>/dev/null || true
sleep 2

echo ""
echo "=== BASELINE COMPARISON ==="

echo "Same tests on working baseline..."
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_comparison.log 2>&1 &
BASE_PID=$!
sleep 6

echo "Baseline Test 1:"
printf "*3\r\n\$3\r\nSET\r\n\$5\r\ntest1\r\n\$6\r\nvalue1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "Baseline GET: "
printf "*2\r\n\$3\r\nGET\r\n\$5\r\ntest1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo "Baseline Test 2:"
{
printf "*3\r\n\$3\r\nSET\r\n\$5\r\ntest2\r\n\$6\r\nvalue2\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$5\r\ntest2\r\n"
} | nc -w 3 127.0.0.1 6379

kill $BASE_PID 2>/dev/null || true

echo ""
echo "=== ROOT CAUSE ANALYSIS ==="
echo "🔍 DIAGNOSTIC PATTERNS:"
echo "  → If baseline works but unified fails: Implementation bug in unified version"
echo "  → If both work inconsistently: Network/timing issues"
echo "  → If unified has partial success: Race conditions or event loop issues"
echo "  → If SET works but GET fails: Cache access or routing problems"
echo ""
echo "🔍 POSSIBLE ROOT CAUSES:"
echo "  1. Event loop blocking/deadlock in unified version"
echo "  2. Socket handling differences causing connection issues"
echo "  3. Response buffering/flushing problems"
echo "  4. Race conditions in cross-core message passing"
echo "  5. Memory corruption or resource leaks"
echo ""
echo "$(date): Deep dive analysis complete"












