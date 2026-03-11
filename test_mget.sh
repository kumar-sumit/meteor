#!/bin/bash

# Test script for MGET implementation

echo "🧪 METEOR MGET FUNCTIONALITY TEST"
echo "================================="

# Start server in background
echo "Starting Meteor server with MGET support..."
./meteor-server-mget-test -c 2 -s 2 -p 6379 &
SERVER_PID=$!

# Wait for server to start
sleep 3

echo "Server PID: $SERVER_PID"
echo ""

# Test basic functionality
echo "🔧 Setting up test data..."
redis-cli -p 6379 SET key1 "value1"
redis-cli -p 6379 SET key2 "value2"  
redis-cli -p 6379 SET key3 "value3"
redis-cli -p 6379 SET missing_key "this_will_be_deleted"
redis-cli -p 6379 DEL missing_key

echo ""
echo "📊 Testing MGET functionality..."

# Test MGET with existing keys
echo "Test 1: MGET with all existing keys"
echo "Command: redis-cli -p 6379 MGET key1 key2 key3"
redis-cli -p 6379 MGET key1 key2 key3
echo ""

# Test MGET with missing keys
echo "Test 2: MGET with mixed existing and missing keys"
echo "Command: redis-cli -p 6379 MGET key1 missing_key key3"
redis-cli -p 6379 MGET key1 missing_key key3
echo ""

# Test MGET with single key (should work like GET)
echo "Test 3: MGET with single key"
echo "Command: redis-cli -p 6379 MGET key1"
redis-cli -p 6379 MGET key1
echo ""

# Compare with individual GET commands
echo "Test 4: Compare with individual GET commands"
echo "Individual GETs:"
echo -n "GET key1: "
redis-cli -p 6379 GET key1
echo -n "GET key2: "
redis-cli -p 6379 GET key2
echo -n "GET key3: "
redis-cli -p 6379 GET key3
echo ""

# Test that GET still works (regression test)
echo "🔍 Regression Test: Verify GET command still works"
echo "GET key1:"
redis-cli -p 6379 GET key1
echo ""

# Performance comparison test
echo "⚡ Basic Performance Test"
echo "MGET performance:"
time redis-cli -p 6379 MGET key1 key2 key3 > /dev/null
echo "Individual GET performance:"
time (redis-cli -p 6379 GET key1 > /dev/null && redis-cli -p 6379 GET key2 > /dev/null && redis-cli -p 6379 GET key3 > /dev/null)
echo ""

# Clean up
echo "🧹 Cleaning up..."
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null

echo "✅ MGET Test Complete!"









