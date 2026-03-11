#!/bin/bash

# **PHASE 6 STEP 1: Simple Diagnostic Test**
# Test Phase 6 Step 1 with minimal configuration to identify issues

echo "🔍 Phase 6 Step 1 - Diagnostic Test"
echo "===================================="

# Kill any existing servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo "🚀 Testing Phase 6 Step 1 with minimal config..."
echo "Config: 1 core, 2 shards, 512MB RAM, port 6384"

# Start with very minimal configuration
timeout 15 ./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6384 -c 1 -s 2 -m 512 -l > diagnostic.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
sleep 8

# Check if process is still running
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server process is running"
    
    # Check if it's listening
    if ss -tlnp 2>/dev/null | grep :6384; then
        echo "✅ Server is listening on port 6384"
        
        # Test basic PING
        echo "🔍 Testing PING command..."
        echo "PING" | timeout 3 nc 127.0.0.1 6384 && echo "✅ PING successful" || echo "❌ PING failed"
        
        # Run quick benchmark
        echo "📊 Running quick benchmark..."
        timeout 10 memtier_benchmark -h 127.0.0.1 -p 6384 -t 1 -c 2 -n 1000 --ratio=1:1 --hide-histogram
        
    else
        echo "❌ Server not listening on port 6384"
    fi
else
    echo "❌ Server process died"
fi

# Kill server
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true

echo
echo "📋 Diagnostic Log:"
echo "=================="
cat diagnostic.log

echo
echo "🔍 Process status during test:"
ps aux | grep meteor | grep -v grep || echo "No meteor processes found"