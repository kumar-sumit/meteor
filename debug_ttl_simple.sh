#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== SIMPLE TTL COMMAND DEBUG ==="
echo "$(date): Debugging TTL command parsing and execution"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "Starting LRU+TTL server for debugging..."
nohup ./meteor_lru_ttl -c 4 -s 4 > simple_debug.log 2>&1 &
SIMPLE_PID=$!
sleep 8

echo ""
echo "=== BASIC FUNCTIONALITY CHECK ==="

echo -n "Test 1 - SET: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ndebugkey\r\n\$9\r\ndebugval\r\n" | nc -w 3 127.0.0.1 6379

echo -n "Test 1 - GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\ndebugkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "=== TTL COMMAND DEBUGGING ==="

echo -n "Test 2 - EXPIRE (expect :1 for success): "
printf "*3\r\n\$6\r\nEXPIRE\r\n\$8\r\ndebugkey\r\n\$2\r\n10\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "Test 2 - TTL (expect remaining seconds): "
printf "*2\r\n\$3\r\nTTL\r\n\$8\r\ndebugkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "=== COMMAND CASE TESTING ==="

echo -n "Test 3 - expire (lowercase): "
printf "*3\r\n\$6\r\nexpire\r\n\$8\r\ndebugkey\r\n\$1\r\n5\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "Test 3 - ttl (lowercase): "
printf "*2\r\n\$3\r\nttl\r\n\$8\r\ndebugkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "=== COMPARISON WITH BASELINE ==="
kill $SIMPLE_PID 2>/dev/null || true
sleep 3

echo "Testing same operations on working baseline..."
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_debug.log 2>&1 &
BASE_PID=$!
sleep 6

echo -n "Baseline SET: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasekey\r\n\$9\r\nbaseval\r\n" | nc -w 2 127.0.0.1 6379

echo -n "Baseline GET: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

kill $BASE_PID 2>/dev/null || true

echo ""
echo "=== DEBUG ANALYSIS ==="
echo "🔍 If TTL commands return empty or wrong values:"
echo "  - Command parsing issue (case sensitivity?)"
echo "  - RESP protocol formatting problem"  
echo "  - Command routing not reaching TTL handlers"
echo ""
echo "🔍 If basic SET/GET fails in LRU+TTL but works in baseline:"
echo "  - Cache implementation regression"
echo "  - Memory corruption in enhanced Entry struct"
echo ""
echo "$(date): Simple TTL debug complete"












