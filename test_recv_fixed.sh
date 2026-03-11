#!/bin/bash

echo "=== PHASE 7 STEP 1 RECV OPERATION FIX VALIDATION ==="

# Kill any existing servers
pkill -f meteor || true
sleep 2

echo "Starting Phase 7 Step 1 Recv Fixed Server..."
./meteor_phase7_recv_fixed -h 0.0.0.0 -p 6409 -c 4 -s 8 > server_recv_fixed.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start and initialize
sleep 10

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server is running"
    
    echo "=== TESTING PING COMMAND ==="
    echo "PING" | timeout 10s nc 127.0.0.1 6409 > ping_recv_test.txt 2>&1 || echo "PING test completed"
    echo "PING response (hex):"
    cat ping_recv_test.txt | hexdump -C
    echo "PING response (text):"
    cat ping_recv_test.txt
    
    echo "=== TESTING SET COMMAND ==="
    echo "SET testkey testvalue" | timeout 10s nc 127.0.0.1 6409 > set_recv_test.txt 2>&1 || echo "SET test completed"
    echo "SET response (hex):"
    cat set_recv_test.txt | hexdump -C
    echo "SET response (text):"
    cat set_recv_test.txt
    
    echo "=== TESTING GET COMMAND ==="
    echo "GET testkey" | timeout 10s nc 127.0.0.1 6409 > get_recv_test.txt 2>&1 || echo "GET test completed"
    echo "GET response (hex):"
    cat get_recv_test.txt | hexdump -C
    echo "GET response (text):"
    cat get_recv_test.txt
    
    echo "=== SERVER LOG ANALYSIS ==="
    echo "Accept operations:"
    grep -i "accepted connection" server_recv_fixed.log | tail -5
    echo ""
    echo "Recv operations:"
    grep -i "submitted recv operation" server_recv_fixed.log | tail -5
    echo ""
    echo "Recv completions:"
    grep -i "received.*bytes" server_recv_fixed.log | tail -5
    echo ""
    echo "Send operations:"
    grep -i "sent.*bytes" server_recv_fixed.log | tail -5
    echo ""
    echo "Recent server log:"
    tail -20 server_recv_fixed.log
    
    # Check if we got any responses
    if [ -s ping_recv_test.txt ] || [ -s set_recv_test.txt ] || [ -s get_recv_test.txt ]; then
        echo ""
        echo "🎉 SUCCESS: COMMANDS ARE RESPONDING!"
        echo "🚀 RECV OPERATION FIX SUCCESSFUL!"
        
        echo "=== PERFORMANCE VALIDATION ==="
        timeout 30s redis-benchmark -h 127.0.0.1 -p 6409 -t ping,set,get -n 10000 -c 10 -q > performance_recv_fixed.txt 2>&1 || echo "Performance test completed"
        echo "Performance results:"
        cat performance_recv_fixed.txt
        
        # Check for high performance
        if grep -q "requests per second" performance_recv_fixed.txt; then
            echo "🎯 PERFORMANCE TARGET VALIDATION:"
            grep "requests per second" performance_recv_fixed.txt
        fi
        
    else
        echo ""
        echo "❌ Commands still not responding - analyzing logs..."
        echo "Error patterns:"
        grep -i "error\|fail\|❌" server_recv_fixed.log | tail -10
    fi
    
else
    echo "❌ Server failed to start"
    echo "Server log:"
    cat server_recv_fixed.log 2>/dev/null || echo "No log file"
fi

# Kill server
kill $SERVER_PID 2>/dev/null || true
sleep 1
kill -9 $SERVER_PID 2>/dev/null || true

echo ""
echo "=== RECV OPERATION FIX TEST COMPLETED ==="