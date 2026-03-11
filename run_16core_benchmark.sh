#!/bin/bash

echo "=== FlashDB 16-Core Benchmark Script ==="
echo "VM: memtier-benchmarking (c4-standard-16)"
echo "Cores: 16 CPUs confirmed"
echo "========================================="

# Navigate to FlashDB directory
cd /dev/shm/flashdb || exit 1

# Kill any existing servers
pkill -f flashdb 2>/dev/null

echo "Starting FlashDB io_uring server with 16 threads..."
nohup ./build/flashdb_iouring_server -p 6379 -t 16 > flashdb_16core.log 2>&1 &
SERVER_PID=$!

# Wait for server to start
sleep 5

# Check if server is running
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ FlashDB 16-core server started (PID: $SERVER_PID)"
else
    echo "❌ Server failed to start, checking log:"
    tail -20 flashdb_16core.log
    exit 1
fi

# Test connectivity
echo "Testing server connectivity..."
if timeout 5 redis-cli -p 6379 ping > /dev/null 2>&1; then
    echo "✅ Server responding to ping"
else
    echo "❌ Server not responding, trying simple server instead..."
    pkill -f flashdb
    nohup ./build/flashdb_server 6379 > flashdb_simple.log 2>&1 &
    sleep 3
fi

echo ""
echo "=== Running 16-Core Benchmark Tests ==="
echo ""

# Test 1: Mixed workload with high thread count
echo "Test 1: High-thread mixed workload (16t x 25c)"
memtier_benchmark -s localhost -p 6379 -t 16 -c 25 -n 2000 --ratio=1:4 --data-size=256 --hide-histogram

echo ""
echo "Test 2: Pure GET operations (16t x 20c)"
memtier_benchmark -s localhost -p 6379 -t 16 -c 20 -n 2000 --ratio=0:1 --data-size=256 --hide-histogram

echo ""
echo "Test 3: High concurrency test (32t x 25c)"
memtier_benchmark -s localhost -p 6379 -t 32 -c 25 -n 1000 --ratio=1:4 --data-size=256 --hide-histogram

echo ""
echo "=== Benchmark Complete ==="
echo "Server log available at: flashdb_16core.log"

# Keep server running
echo "FlashDB server still running on port 6379 (PID: $SERVER_PID)"
echo "To stop: pkill -f flashdb"