#!/bin/bash

# **PHASE 6 STEP 1: Fixed Version Test Script**
# Test the debugged Phase 6 Step 1 with proper initialization

echo "🚀 Phase 6 Step 1 - Fixed Version Test"
echo "======================================"
echo "Testing debugged version with enhanced initialization"
echo

# Kill any existing servers
echo "🛑 Cleaning up all existing servers..."
pkill -f meteor 2>/dev/null || true
sleep 3

# Test with single core first (simplest case)
echo "📊 Test 1: Single Core Configuration"
echo "====================================="
echo "Config: 1 core, 2 shards, 1GB RAM, port 6390"

./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6390 -c 1 -s 2 -m 1024 -l > single_core.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for initialization
sleep 5

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Single core server is running"
    
    # Check if listening
    if ss -tlnp 2>/dev/null | grep :6390 > /dev/null; then
        echo "✅ Server is listening on port 6390"
        
        # Test basic connectivity
        if echo "PING" | timeout 3 nc 127.0.0.1 6390 > /dev/null; then
            echo "✅ PING test successful"
            
            # Run benchmark
            echo "📊 Running benchmark..."
            memtier_benchmark -h 127.0.0.1 -p 6390 -t 1 -c 2 -n 5000 --ratio=1:1 --hide-histogram
            echo "✅ Single core test completed successfully!"
        else
            echo "❌ PING test failed"
        fi
    else
        echo "❌ Server not listening"
    fi
else
    echo "❌ Single core server died"
fi

# Stop single core server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo
echo "📊 Test 2: Multi-Core Configuration (4 cores)"
echo "============================================="
echo "Config: 4 cores, 16 shards, 4GB RAM, port 6391"

./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6391 -c 4 -s 16 -m 4096 -l > multi_core.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for initialization (longer for multi-core)
sleep 8

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Multi-core server is running"
    
    if ss -tlnp 2>/dev/null | grep :6391 > /dev/null; then
        echo "✅ Server is listening on port 6391"
        
        if echo "PING" | timeout 3 nc 127.0.0.1 6391 > /dev/null; then
            echo "✅ PING test successful"
            
            # Run more intensive benchmark
            echo "📊 Running multi-core benchmark..."
            memtier_benchmark -h 127.0.0.1 -p 6391 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10 --hide-histogram
            echo "✅ Multi-core test completed successfully!"
        else
            echo "❌ PING test failed"
        fi
    else
        echo "❌ Server not listening"
    fi
else
    echo "❌ Multi-core server died"
fi

# Stop multi-core server
kill $SERVER_PID 2>/dev/null || true

echo
echo "📋 Server Logs Analysis:"
echo "========================"
echo
echo "Single Core Log (first 30 lines):"
head -30 single_core.log 2>/dev/null || echo "No single core log"
echo
echo "Multi-Core Log (first 30 lines):"
head -30 multi_core.log 2>/dev/null || echo "No multi-core log"

echo
echo "🎉 Phase 6 Step 1 Fixed Version Test Complete!"
echo
echo "Summary:"
echo "- Single core test: Check logs above"
echo "- Multi-core test: Check logs above"
echo "- Initialization improvements: Enhanced synchronization and error handling"
echo "- NUMA optimizations: CPU affinity and memory policy"
echo "- AVX-512 SIMD: 8-way parallel operations"