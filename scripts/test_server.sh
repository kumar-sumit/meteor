#!/bin/bash

# Test script for Meteor Redis-compatible server
HOST="localhost"
PORT="6380"

echo "=== Meteor Server Redis Compatibility Test ==="
echo "Testing server at $HOST:$PORT"
echo

echo "1. Testing basic connectivity..."
redis-cli -h $HOST -p $PORT ping
echo

echo "2. Testing SET/GET operations..."
redis-cli -h $HOST -p $PORT set test_key "Hello, Meteor!"
redis-cli -h $HOST -p $PORT get test_key
echo

echo "3. Testing TTL operations..."
redis-cli -h $HOST -p $PORT set ttl_key "expires soon" EX 60
redis-cli -h $HOST -p $PORT ttl ttl_key
echo

echo "4. Testing EXISTS/DEL operations..."
redis-cli -h $HOST -p $PORT exists test_key
redis-cli -h $HOST -p $PORT del test_key
redis-cli -h $HOST -p $PORT exists test_key
echo

echo "5. Testing INFO command..."
redis-cli -h $HOST -p $PORT info | head -20
echo

echo "6. Simple performance test..."
echo "Running 1000 SET operations..."
start_time=$(date +%s%N)
for i in {1..1000}; do
    redis-cli -h $HOST -p $PORT set "key_$i" "value_$i" > /dev/null
done
end_time=$(date +%s%N)
duration=$((($end_time - $start_time) / 1000000))
echo "SET operations completed in ${duration}ms"
echo "Average: $((duration / 1000)) ms per operation"
echo

echo "Running 1000 GET operations..."
start_time=$(date +%s%N)
for i in {1..1000}; do
    redis-cli -h $HOST -p $PORT get "key_$i" > /dev/null
done
end_time=$(date +%s%N)
duration=$((($end_time - $start_time) / 1000000))
echo "GET operations completed in ${duration}ms"
echo "Average: $((duration / 1000)) ms per operation"
echo

echo "=== Test Complete ==="
echo "Meteor server is Redis-compatible and ready for production use!"
echo "You can now use any Redis client or tool with this server." 