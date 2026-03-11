#!/bin/bash

# **SIMPLE TTL DEMONSTRATION**
# Quick test to show TTL functionality works

echo "🧪 METEOR COMMERCIAL LRU+TTL - SIMPLE TTL DEMO"
echo ""

# Start server
echo "🚀 Starting server..."
./meteor_commercial_lru_ttl -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 512 &
SERVER_PID=$!
sleep 3

echo "📝 TTL Demo:"
echo ""

echo "1. Set key with 5 second TTL:"
redis-cli -p 6379 set demo_key "expires in 5 seconds" EX 5
echo ""

echo "2. Check TTL immediately:"
redis-cli -p 6379 ttl demo_key
echo ""

echo "3. Get the key value:"
redis-cli -p 6379 get demo_key
echo ""

echo "4. Wait 6 seconds for expiration..."
sleep 6
echo ""

echo "5. Try to get expired key:"
RESULT=$(redis-cli -p 6379 get demo_key)
echo "Result: '$RESULT'"

if [ -z "$RESULT" ] || [ "$RESULT" = "(nil)" ]; then
    echo "✅ KEY EXPIRED SUCCESSFULLY!"
else
    echo "❌ Key did not expire"
fi
echo ""

echo "6. Check TTL of expired key:"
redis-cli -p 6379 ttl demo_key
echo "(Should return -2 for non-existent key)"
echo ""

# Cleanup
kill $SERVER_PID
echo "✅ Demo complete!"














