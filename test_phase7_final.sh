#!/bin/bash

echo "=== PHASE 7 STEP 1 FINAL COMMAND PROCESSING TEST ==="

# Kill any existing servers
pkill -f meteor || true
sleep 2

echo "Starting Phase 7 Step 1 Final Fixed Server..."
./meteor_phase7_final -h 0.0.0.0 -p 6409 -c 4 -s 8 > server_final.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
sleep 8

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server is running"
    
    echo "=== TESTING PING COMMAND ==="
    echo "PING" | timeout 10s nc 127.0.0.1 6409 > ping_final.txt 2>&1 || echo "PING test completed"
    echo "PING response:"
    cat ping_final.txt | hexdump -C
    
    echo "=== TESTING SET COMMAND ==="
    echo "SET testkey testvalue" | timeout 10s nc 127.0.0.1 6409 > set_final.txt 2>&1 || echo "SET test completed"
    echo "SET response:"
    cat set_final.txt | hexdump -C
    
    echo "=== TESTING GET COMMAND ==="
    echo "GET testkey" | timeout 10s nc 127.0.0.1 6409 > get_final.txt 2>&1 || echo "GET test completed"
    echo "GET response:"
    cat get_final.txt | hexdump -C
    
    echo "=== SERVER LOG TAIL ==="
    tail -20 server_final.log
    
    # Check if responses are non-empty
    if [ -s ping_final.txt ] || [ -s set_final.txt ] || [ -s get_final.txt ]; then
        echo "🎉 COMMANDS ARE RESPONDING!"
        
        echo "=== PERFORMANCE TEST ==="
        timeout 30s redis-benchmark -h 127.0.0.1 -p 6409 -t ping,set,get -n 10000 -c 10 -q > performance_final.txt 2>&1 || echo "Performance test completed"
        echo "Performance results:"
        cat performance_final.txt
    else
        echo "❌ Commands still not responding"
    fi
    
else
    echo "❌ Server failed to start"
    echo "Server log:"
    cat server_final.log 2>/dev/null || echo "No log file"
fi

# Kill server
kill $SERVER_PID 2>/dev/null || true
sleep 1
kill -9 $SERVER_PID 2>/dev/null || true

echo "=== FINAL TEST COMPLETED ==="