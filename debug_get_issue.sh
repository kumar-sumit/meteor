#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== DEBUG GET ISSUE ==="
echo "$(date): Isolating GET response problem"

pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "Starting debug server..."
nohup ./meteor_ttl_final -c 4 -s 4 > debug.log 2>&1 &
SERVER_PID=$!
sleep 5

echo ""
echo "🔍 DIRECT COMPARISON: Working Baseline vs TTL Implementation"

echo "1. SET operation:"
printf "*3\r\n\$3\r\nSET\r\n\$7\r\ndebugkey\r\n\$8\r\ndebugval\r\n" | nc -w 2 127.0.0.1 6379

echo "2. GET operation (should return value):"
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ndebugkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo "3. EXPIRE operation (confirms key exists):"
printf "*3\r\n\$6\r\nEXPIRE\r\n\$7\r\ndebugkey\r\n\$2\r\n30\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo "4. TTL operation (confirms key and TTL work):"
printf "*2\r\n\$3\r\nTTL\r\n\$7\r\ndebugkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo "5. GET after EXPIRE (should still return value):"
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ndebugkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "6. PING test (basic connectivity):"
printf "*1\r\n\$4\r\nPING\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

kill $SERVER_PID 2>/dev/null || true

echo ""
echo "=== ANALYSIS ==="
echo "If EXPIRE/TTL work but GET fails:"
echo "  → Cache storage works (EXPIRE finds keys)" 
echo "  → TTL logic works (TTL calculates correctly)"
echo "  → Issue is in GET response path specifically"
echo ""
echo "If PING works but GET fails:"
echo "  → Server connectivity fine"
echo "  → Issue in GET response formatting/sending"

echo ""
echo "Server log (last 20 lines):"
tail -20 debug.log












