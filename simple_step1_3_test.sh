#!/bin/bash

echo "🧪 **SIMPLE STEP 1.3 TEST**"
echo "==========================="

# Clean up
pkill -f meteor
sleep 2

echo "🚀 Starting Step 1.3 server..."
./meteor_step1_3_connection_fixed -p 6380 -c 1 > simple_test.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server startup
sleep 10

echo ""
echo "📡 Testing connectivity..."

# Test using nc (netcat) to verify port is open
echo -n "🔍 Port check: "
if nc -z 127.0.0.1 6380 2>/dev/null; then
    echo "✅ Port 6380 is open"
else
    echo "❌ Port 6380 is not accessible"
fi

# Test with redis-cli
echo -n "📡 Redis PING: "
redis-cli -p 6380 ping 2>/dev/null && echo "✅ PING successful" || echo "❌ PING failed"

echo -n "🔧 Redis SET: "
redis-cli -p 6380 set key1 value1 2>/dev/null && echo "✅ SET successful" || echo "❌ SET failed"

echo -n "🔍 Redis GET: "
redis-cli -p 6380 get key1 2>/dev/null && echo "✅ GET successful" || echo "❌ GET failed"

# Check server logs
echo ""
echo "📊 Server status:"
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server process is running"
else
    echo "❌ Server process has stopped"
fi

# Show last few lines of log
echo ""
echo "📋 Recent server activity:"
tail -5 simple_test.log

# Clean up
pkill -f meteor
echo ""
echo "✅ Test complete"















