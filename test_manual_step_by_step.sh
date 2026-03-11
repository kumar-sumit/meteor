#!/bin/bash

# Manual step-by-step testing to identify the exact issue
echo "🔍 MANUAL STEP-BY-STEP TTL DEBUG"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🚀 Starting surgical TTL server..."
nohup ./meteor_surgical_test -c 4 -s 4 > manual_debug.log 2>&1 &
SERVER_PID=$!
sleep 3

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    exit 1
fi

echo "✅ Server started (PID: $SERVER_PID)"
echo ""

# Test each command individually with detailed feedback
echo "=== MANUAL STEP-BY-STEP TESTING ==="

echo -n "Step 1 - PING: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw PING 2>/dev/null)
echo "\"$RESULT\""
if [ "$RESULT" != "PONG" ]; then
    echo "❌ PING failed - server might be broken"
    kill $SERVER_PID 2>/dev/null
    exit 1
fi

sleep 1

echo -n "Step 2 - SET simple_key simple_value: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw SET simple_key simple_value 2>/dev/null)
echo "\"$RESULT\""

sleep 1

echo -n "Step 3 - GET simple_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw GET simple_key 2>/dev/null)
echo "\"$RESULT\""

sleep 1

echo -n "Step 4 - TTL simple_key (should be -1): "
RESULT=$(timeout 5s redis-cli -p 6379 --raw TTL simple_key 2>/dev/null)
echo "\"$RESULT\""

sleep 1

echo -n "Step 5 - DEL simple_key: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw DEL simple_key 2>/dev/null)
echo "\"$RESULT\""

sleep 1

echo -n "Step 6 - Final PING: "
RESULT=$(timeout 5s redis-cli -p 6379 --raw PING 2>/dev/null)
echo "\"$RESULT\""

# Check server status
echo ""
echo -n "Server status: "
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Still running"
else
    echo "❌ Server died"
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=== Server Log (last 15 lines) ==="
tail -15 manual_debug.log

EOF












