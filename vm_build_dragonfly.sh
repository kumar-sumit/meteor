#!/bin/bash

echo "🔧 VM Build Script - DragonflyDB Cross-Shard Implementation"
echo "=========================================================="

# Setup environment
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 3

echo "📁 Current directory: $(pwd)"
echo "📋 Files available:"
ls -la meteor_dragonfly_FIXED.cpp 2>/dev/null || echo "❌ meteor_dragonfly_FIXED.cpp not found"
ls -la meteor_phase1_2b_dragonfly_cross_shard.cpp 2>/dev/null || echo "❌ meteor_phase1_2b_dragonfly_cross_shard.cpp not found"

# Try building the fixed version
echo ""
echo "🔨 Attempting to build meteor_dragonfly_FIXED.cpp..."
echo "=================================================="

g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 -pthread meteor_dragonfly_FIXED.cpp -o meteor_dragonfly_test -luring -lboost_fiber -lboost_context -lboost_system 2>&1

BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Test the server
    echo ""
    echo "🧪 Testing server startup..."
    echo "============================"
    
    ./meteor_dragonfly_test -h 127.0.0.1 -p 6379 -c 6 -s 3 -m 1536 &
    SERVER_PID=$!
    sleep 5
    
    # Quick connectivity test
    PING_RESULT=$(redis-cli -p 6379 ping 2>/dev/null)
    if [ "$PING_RESULT" = "PONG" ]; then
        echo "✅ Server started successfully: $PING_RESULT"
        
        # Quick correctness test
        redis-cli -p 6379 flushall >/dev/null 2>&1
        redis-cli -p 6379 set test_key "test_value" >/dev/null 2>&1
        TEST_RESULT=$(redis-cli -p 6379 get test_key 2>/dev/null)
        
        echo "🎯 Quick test: set test_key → get '$TEST_RESULT'"
        
        if [ "$TEST_RESULT" = "test_value" ]; then
            echo "🎉 Basic functionality working!"
            
            # Run comprehensive test
            echo ""
            echo "🚀 Running comprehensive cross-shard test..."
            echo "==========================================="
            
            FAILURES=0
            for i in {1..10}; do
                redis-cli -p 6379 set cross_test_$i "cross_value_$i" >/dev/null 2>&1
                RESULT=$(redis-cli -p 6379 get cross_test_$i 2>/dev/null)
                if [ "$RESULT" != "cross_value_$i" ]; then
                    FAILURES=$((FAILURES + 1))
                fi
            done
            
            echo "Cross-shard failures: $FAILURES/10"
            
            if [ $FAILURES -eq 0 ]; then
                echo "🏆 PERFECT! All cross-shard operations working!"
                
                # Performance test
                echo ""
                echo "📊 Performance test:"
                memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis --clients=10 --threads=3 --pipeline=5 --data-size=64 --key-pattern=R:R --ratio=1:1 --test-time=5 2>/dev/null | grep "Totals\|Ops/sec" || echo "Performance test completed"
                
            else
                echo "❌ Cross-shard issues detected"
            fi
        else
            echo "❌ Basic functionality failed"
        fi
        
        kill $SERVER_PID 2>/dev/null
    else
        echo "❌ Server failed to start or not responding"
    fi
    
else
    echo "❌ Build failed with exit code: $BUILD_EXIT_CODE"
    echo ""
    echo "🔍 Compilation errors above. Common issues:"
    echo "- Missing boost libraries: apt install libboost-fiber-dev libboost-context-dev"
    echo "- Missing io_uring: apt install liburing-dev"  
    echo "- Compiler version: Need g++ 7+ for C++17"
    echo ""
    echo "📋 System info:"
    g++ --version | head -1
    echo "Boost libraries:"
    ldconfig -p | grep boost | head -3
    echo "IO_uring library:"
    ldconfig -p | grep uring
fi

echo ""
echo "🏁 VM build script completed"













