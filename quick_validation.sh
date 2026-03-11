#!/bin/bash

echo "=== 🚀 QUICK VALIDATION (Phase 7 Step 1) 🚀 ==="
echo "🎯 Testing both epoll and io_uring modes"
echo ""

cd /dev/shm

# Test epoll mode
echo "=== TESTING EPOLL MODE ==="
timeout 30s ./meteor_incremental_iouring -h 127.0.0.1 -p 6379 -c 4 > epoll_test.log 2>&1 &
EPOLL_PID=$!
sleep 5

echo "Testing EPOLL connectivity..."
redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 1000 -c 10 -P 1 -q > epoll_results.txt 2>&1
EPOLL_RESULT=$?

kill $EPOLL_PID 2>/dev/null
wait $EPOLL_PID 2>/dev/null
sleep 2

echo "EPOLL test result: $EPOLL_RESULT"
if [ $EPOLL_RESULT -eq 0 ]; then
    echo "✅ EPOLL mode working"
    cat epoll_results.txt
else
    echo "❌ EPOLL mode failed"
    echo "Error output:"
    cat epoll_results.txt
fi

echo ""
echo "=== TESTING IO_URING MODE ==="
METEOR_USE_IO_URING=1 timeout 30s ./meteor_incremental_iouring -h 127.0.0.1 -p 6379 -c 4 > iouring_test.log 2>&1 &
IOURING_PID=$!
sleep 5

echo "Testing IO_URING connectivity..."
redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 1000 -c 10 -P 1 -q > iouring_results.txt 2>&1
IOURING_RESULT=$?

kill $IOURING_PID 2>/dev/null
wait $IOURING_PID 2>/dev/null

echo "IO_URING test result: $IOURING_RESULT"
if [ $IOURING_RESULT -eq 0 ]; then
    echo "✅ IO_URING mode working"
    cat iouring_results.txt
else
    echo "❌ IO_URING mode failed"
    echo "Error output:"
    cat iouring_results.txt
fi

echo ""
echo "=== SERVER LOGS ==="
echo "EPOLL server log:"
tail -10 epoll_test.log
echo ""
echo "IO_URING server log:"
tail -10 iouring_test.log

echo ""
echo "=== BUILD INFO ==="
echo "Binary info:"
ls -la meteor_incremental_iouring
echo ""
echo "AVX support:"
grep -E "avx|AVX" /proc/cpuinfo | head -3
echo ""
echo "io_uring symbols:"
nm meteor_incremental_iouring | grep io_uring | head -5