#!/bin/bash

# Test all commands in a single redis-cli session
echo "🧪 SURGICAL TTL - SINGLE SESSION TEST"
echo "=========================================="

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

# Kill any existing server
pkill -f meteor 2>/dev/null || true
sleep 2

# Start server
echo "🚀 Starting surgical TTL server..."
nohup ./meteor_surgical_test -c 4 -s 4 > single_session.log 2>&1 &
SERVER_PID=$!
sleep 3

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    exit 1
fi

echo "✅ Server started (PID: $SERVER_PID)"

# Test all commands in a single redis-cli session
echo ""
echo "=== SINGLE SESSION TEST (all commands) ==="

timeout 10s redis-cli -p 6379 << 'REDIS_COMMANDS'
PING
SET test_key test_value  
GET test_key
TTL test_key
DEL test_key
TTL nonexistent_key
PING
REDIS_COMMANDS

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=== Server Log (last 10 lines) ==="
tail -10 single_session.log

EOF












