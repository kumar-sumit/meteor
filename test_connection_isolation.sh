#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== CONNECTION ISOLATION TEST ==="
echo "$(date): Testing if issue is connection reuse vs new connections"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "Starting server for connection isolation test..."
nohup ./cpp/meteor_true_pipeline_unified -c 4 -s 4 > connection_test.log 2>&1 &
CONN_PID=$!
sleep 6

echo ""
echo "✅ TEST 1: Single operation per connection (should all work)"
for i in {1..5}; do
    echo "Connection $i SET:"
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\ntest$i\r\n\$7\r\nval$i\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
    echo "Connection $i GET:"
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\ntest$i\r\n" | timeout 3s nc -w 3 127.0.0.1 6379
done

echo ""
echo "✅ TEST 2: Multiple operations same connection (may hang)"
echo "Same connection test:"
{
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nsameconn\r\n\$9\r\nsameval\r\n"
    sleep 0.5
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nsameconn\r\n"
    sleep 0.5
    printf "*3\r\n\$3\r\nSET\r\n\$9\r\nsameconn2\r\n\$10\r\nsameval2\r\n"
} | timeout 10s nc -w 10 127.0.0.1 6379

echo ""
echo "✅ TEST 3: Baseline comparison (should work perfectly)"
kill $CONN_PID 2>/dev/null || true
sleep 3

echo "Starting baseline for comparison..."
nohup ./cpp/meteor_final_correct -c 4 -s 4 > baseline_conn.log 2>&1 &
BASE_PID=$!
sleep 6

echo "Baseline multiple operations:"
for i in {1..5}; do
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbase$i\r\n\$9\r\nbaseval$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "Baseline GET $i: "
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbase$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "Baseline same connection:"
{
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbaseconn\r\n\$9\r\nbaseval\r\n"
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbaseconn\r\n"
    printf "*3\r\n\$3\r\nSET\r\n\$9\r\nbaseconn2\r\n\$10\r\nbaseval2\r\n"
} | nc -w 5 127.0.0.1 6379

kill $BASE_PID 2>/dev/null || true

echo ""
echo "=== CONNECTION ISSUE DIAGNOSIS ==="
echo "🔍 PATTERNS:"
echo "  → If unified single connections work: Data storage fixed ✅"
echo "  → If unified same connection hangs: Connection handling issue ❌"
echo "  → If baseline works perfectly: Implementation difference in unified ❌"
echo ""
echo "🔍 LIKELY CAUSES:"
echo "  1. Connection state not properly reset after first operation"
echo "  2. Event loop blocking after processing first command"
echo"  3. Response flushing issues preventing next command processing"
echo "  4. Socket buffer issues or incomplete response handling"
echo ""
echo "$(date): Connection isolation test complete"












