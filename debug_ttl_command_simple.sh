#!/bin/bash

# Quick debug of TTL command to see what's happening
echo "🔍 TTL COMMAND DEBUG"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

# Start surgical TTL server with debugging
echo "🚀 Starting server with debugging..."
nohup ./meteor_surgical_test -c 4 -s 4 > debug_ttl.log 2>&1 &
SERVER_PID=$!
sleep 3

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    exit 1
fi

echo "✅ Server started (PID: $SERVER_PID)"

# Test just TTL command in isolation
echo ""
echo "=== TTL COMMAND ISOLATION TEST ==="
echo -n "TTL test_nonexistent_key: "
TTL_RESULT=$(timeout 5s redis-cli -p 6379 TTL test_nonexistent_key 2>&1)
echo "\"$TTL_RESULT\""

echo -n "Server status after TTL: "
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server still running"
else
    echo "❌ Server died"
fi

echo ""
echo "=== Test PING after TTL ==="
echo -n "PING: "
PING_RESULT=$(timeout 5s redis-cli -p 6379 PING 2>&1)
echo "\"$PING_RESULT\""

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=== SERVER LOG (last 10 lines) ==="
tail -10 debug_ttl.log

EOF












