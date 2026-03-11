#!/bin/bash

# Debug the GET-after-SET issue specifically
echo "🔍 GET-AFTER-SET ISSUE DEBUG"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🚀 Starting surgical TTL server..."
nohup ./meteor_surgical_test -c 4 -s 4 > get_set_debug.log 2>&1 &
SERVER_PID=$!
sleep 3

echo "✅ Server started (PID: $SERVER_PID)"
echo ""

# Test the specific issue: GET after SET
echo "=== GET-AFTER-SET DEBUGGING ==="

echo -n "Test A1 - PING: "
RESULT=$(timeout 3s redis-cli -p 6379 --raw PING 2>/dev/null)
echo "\"$RESULT\""

echo -n "Test A2 - SET key1 value1: "
RESULT=$(timeout 3s redis-cli -p 6379 --raw SET key1 value1 2>/dev/null)
echo "\"$RESULT\""

echo -n "Test A3 - GET key1 (this should work but fails): "
RESULT=$(timeout 3s redis-cli -p 6379 --raw GET key1 2>/dev/null)
echo "\"$RESULT\""

# Try a different key to see if it's key-specific
echo -n "Test A4 - SET key2 value2: "
RESULT=$(timeout 3s redis-cli -p 6379 --raw SET key2 value2 2>/dev/null)
echo "\"$RESULT\""

echo -n "Test A5 - GET key2: "
RESULT=$(timeout 3s redis-cli -p 6379 --raw GET key2 2>/dev/null)
echo "\"$RESULT\""

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=== Server Log Analysis ==="
echo "Looking for errors or unusual patterns..."
tail -20 get_set_debug.log | grep -E "(error|Error|ERROR|failed|Failed|FAILED|exception|Exception)" || echo "No obvious errors found"

echo ""
echo "Last 10 lines of log:"
tail -10 get_set_debug.log

EOF












