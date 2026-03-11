#!/bin/bash

echo "🧪 COMPREHENSIVE FIXED BUFFER TEST SUITE"
echo "========================================"

# Kill any existing servers
pkill -f meteor_fixed_buffers 2>/dev/null || true
sleep 2

echo ""
echo "🔧 Test 1: Basic io_uring connectivity (no fixed buffers)"
echo "--------------------------------------------------------"
timeout 5 bash -c 'METEOR_USE_IO_URING=1 ./meteor_fixed_buffers -h 127.0.0.1 -p 6390 -c 1' &
sleep 2
echo "Testing PING..."
redis-cli -p 6390 ping
echo "Testing SET/GET..."
redis-cli -p 6390 set test_key "hello_world"
redis-cli -p 6390 get test_key
pkill -f meteor_fixed_buffers
sleep 1

echo ""
echo "🔧 Test 2: io_uring with fixed buffers enabled"
echo "---------------------------------------------"
timeout 5 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 METEOR_DEBUG_FIXED_BUFFERS=1 ./meteor_fixed_buffers -h 127.0.0.1 -p 6391 -c 1' &
sleep 2
echo "Testing PING with fixed buffers..."
redis-cli -p 6391 ping
echo "Testing SET/GET with fixed buffers..."
redis-cli -p 6391 set fixed_test "zero_copy_buffer"
redis-cli -p 6391 get fixed_test
pkill -f meteor_fixed_buffers
sleep 1

echo ""
echo "🔧 Test 3: Performance comparison - Regular vs Fixed Buffers"
echo "----------------------------------------------------------"
echo "Testing regular io_uring performance..."
timeout 10 bash -c 'METEOR_USE_IO_URING=1 ./meteor_fixed_buffers -h 127.0.0.1 -p 6392 -c 1' &
sleep 3
echo "Running benchmark (regular)..."
redis-benchmark -p 6392 -c 10 -n 10000 -t set -q | head -1
pkill -f meteor_fixed_buffers
sleep 2

echo "Testing fixed buffer io_uring performance..."
timeout 10 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 ./meteor_fixed_buffers -h 127.0.0.1 -p 6393 -c 1' &
sleep 3
echo "Running benchmark (fixed buffers)..."
redis-benchmark -p 6393 -c 10 -n 10000 -t set -q | head -1
pkill -f meteor_fixed_buffers
sleep 2

echo ""
echo "🔧 Test 4: Multi-core with fixed buffers"
echo "---------------------------------------"
timeout 10 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 ./meteor_fixed_buffers -h 127.0.0.1 -p 6394 -c 4' &
sleep 3
echo "Testing multi-core fixed buffer connectivity..."
redis-cli -p 6394 ping
echo "Running multi-core benchmark..."
redis-benchmark -p 6394 -c 20 -n 20000 -t set -q | head -1
pkill -f meteor_fixed_buffers
sleep 2

echo ""
echo "🔧 Test 5: SQPOLL + Fixed Buffers (Ultimate Configuration)"
echo "--------------------------------------------------------"
timeout 10 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 METEOR_USE_SQPOLL=1 ./meteor_fixed_buffers -h 127.0.0.1 -p 6395 -c 2' &
sleep 3
echo "Testing SQPOLL + fixed buffers..."
redis-cli -p 6395 ping
echo "Running ultimate configuration benchmark..."
redis-benchmark -p 6395 -c 10 -n 10000 -t set -q | head -1
pkill -f meteor_fixed_buffers

echo ""
echo "✅ FIXED BUFFER TEST SUITE COMPLETE"
echo "===================================="