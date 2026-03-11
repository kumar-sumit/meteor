#!/bin/bash
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
echo "🔨 Quick compilation test"
echo "File check:"
ls -la meteor_dragonfly_FIXED.cpp
echo ""
echo "Attempting compilation..."
g++ -std=c++17 -O0 -DHAS_LINUX_EPOLL -pthread meteor_dragonfly_FIXED.cpp -o test_build -luring -lboost_fiber -lboost_context -lboost_system
echo "Exit code: $?"













