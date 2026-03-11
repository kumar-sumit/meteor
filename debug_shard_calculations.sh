#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== SHARD CALCULATION DEBUG ==="
echo "$(date): Debug shard vs core calculations"

pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== TESTING BASELINE SHARD BEHAVIOR ==="

echo "Starting baseline server for reference..."
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_debug.log 2>&1 &
BASE_PID=$!
sleep 6

echo "Testing baseline with specific keys to understand shard distribution:"

# Test keys that hash to different values
echo -n "SET testkey1: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntestkey1\r\n\$9\r\ntestval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET testkey1: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntestkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "SET testkey2: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntestkey2\r\n\$9\r\ntestval2\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET testkey2: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntestkey2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "SET testkey3: "  
printf "*3\r\n\$3\r\nSET\r\n\$8\r\ntestkey3\r\n\$9\r\ntestval3\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET testkey3: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\ntestkey3\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

# Test pipeline vs single command on baseline
echo ""
echo "Testing pipeline vs single on baseline:"
echo "Pipeline SET+GET:"
{
printf "*3\r\n\$3\r\nSET\r\n\$8\r\npipetest\r\n\$9\r\npipeval\r\n"
printf "*2\r\n\$3\r\nGET\r\n\$8\r\npipetest\r\n"
} | nc -w 3 127.0.0.1 6379

echo "Single SET then GET:"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nsinglekey\r\n\$10\r\nsingleval\r\n" | nc -w 2 127.0.0.1 6379  
echo -n "Single GET: "
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nsinglekey\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

kill $BASE_PID 2>/dev/null || true

echo ""
echo "=== ANALYSIS ==="
echo "🔍 If baseline works for both single and pipeline:"
echo "  → Shard calculations are consistent between modes"
echo "  → Issue is in unified implementation"
echo ""
echo "🔍 If baseline fails for some keys but not others:"
echo "  → Cross-core routing is working"  
echo "  → Keys hash to different cores/shards correctly"
echo ""
echo "🔍 Next step: Compare exact hash calculations"
echo "  → total_shards vs num_cores differences"
echo "  → shard_id % num_cores mapping"
echo ""
echo "$(date): Shard calculation debug complete"












