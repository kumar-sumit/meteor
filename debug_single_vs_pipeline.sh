#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== DEBUG: SINGLE vs PIPELINE DATA STORAGE ==="
echo "$(date): Debugging why single commands don't store data but pipeline commands do"

pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== CONTROLLED DEBUG TEST ==="

echo "Starting unified server for debugging..."
nohup ./cpp/meteor_true_pipeline_unified -c 4 -s 4 > debug_storage.log 2>&1 &
DEBUG_PID=$!
sleep 8

echo "Test 1: Single command sequence (SET then GET separately)"
echo "Single SET:"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nsinglekey\r\n\$10\r\nsingleval\r\n" | nc -w 3 127.0.0.1 6379
sleep 1
echo "Single GET (should find the data):"
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nsinglekey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "Test 2: Pipeline sequence (SET and GET together)"
echo "Pipeline SET+GET:"
{
printf "*3\r\n\$3\r\nSET\r\n\$8\r\npipekey\r\n\$9\r\npipeval\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$8\r\npipekey\r\n"
} | nc -w 3 127.0.0.1 6379

echo ""
echo "Test 3: Cross-reference test (SET as single, GET as pipeline)"
echo "Single SET:"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ncrosskey\r\n\$9\r\ncrossval\r\n" | nc -w 3 127.0.0.1 6379
sleep 1
echo "Pipeline GET (should find single SET data):"
{
printf "*2\r\n\$3\r\nGET\r\n\$8\r\ncrosskey\r\n"
} | nc -w 3 127.0.0.1 6379

echo ""
echo "Test 4: Same key different approaches"
echo "Pipeline SET:"
{
printf "*3\r\n\$3\r\nSET\r\n\$7\r\ntestkey\r\n\$8\r\npipeval\r\n"
} | nc -w 3 127.0.0.1 6379
sleep 1
echo "Single GET:"
printf "*2\r\n\$3\r\nGET\r\n\$7\r\ntestkey\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

kill $DEBUG_PID 2>/dev/null || true

echo ""
echo "=== DEBUG ANALYSIS ==="
echo "🔍 ROOT CAUSE PATTERNS:"
echo "  → If single SET + single GET = fail: Data not persisting in single mode"
echo "  → If pipeline SET+GET = works: Data persists within pipeline context"
echo "  → If single SET + pipeline GET = works: Data persists across contexts"
echo "  → If pipeline SET + single GET = works: Mixed contexts work"
echo ""
echo "🔍 LIKELY CAUSES:"
echo "  1. Connection state affecting data persistence (is_pipelined flag)"
echo "  2. Response buffering preventing data commit"
echo "  3. Cache instance isolation between single vs pipeline processing"
echo "  4. Timing issue - GET processed before SET completes"
echo ""
echo "$(date): Debug single vs pipeline complete"












