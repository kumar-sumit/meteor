#!/bin/bash
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor || true

# Quick build test
echo "Building..."
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 meteor_debug.cpp -o test_meteor -luring -lboost_fiber -lboost_context -lboost_system -pthread

if [ $? -ne 0 ]; then
    echo "BUILD FAILED"
    exit 1
fi

echo "BUILD OK"

# Start server
./test_meteor -c 6 -s 3 &
SERVER_PID=$!
sleep 5

# Test
echo "Testing..."
redis-cli ping
echo "SET test:"
redis-cli set key1 val1
echo "GET test:"
redis-cli get key1

# Cleanup
kill $SERVER_PID

echo "Test complete"













