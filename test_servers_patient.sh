#!/bin/bash

# Patient server testing with longer timeouts and retries

echo "🔬 PATIENT SERVER TESTING"
echo "========================="

cd /mnt/externalDisk/meteor

# Function to test server with retries
test_server_patient() {
    local config_name=$1
    local max_attempts=10
    local attempt=1
    
    echo "🔍 Testing $config_name server connectivity (patient mode)..."
    
    while [ $attempt -le $max_attempts ]; do
        echo "   🔄 Attempt $attempt/$max_attempts..."
        
        # Check if server process is running
        if pgrep -f meteor > /dev/null; then
            echo "   ✅ Server process is running"
            
            # Test PING with longer timeout
            ping_result=$(echo -e "PING\r" | timeout 10 nc -w 3 127.0.0.1 6379 2>/dev/null | tr -d '\r' | head -1)
            if [[ "$ping_result" == *"PONG"* ]]; then
                echo "   ✅ PING successful: $ping_result"
                
                # Test SET/GET
                echo "   🧪 Testing SET/GET commands..."
                set_result=$(echo -e "SET test:patient:$attempt value$attempt\r" | timeout 5 nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r' | head -1)
                get_result=$(echo -e "GET test:patient:$attempt\r" | timeout 5 nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r' | head -1)
                
                if [[ "$set_result" == *"OK"* ]]; then
                    echo "   ✅ SET successful: $set_result"
                fi
                if [[ "$get_result" == *"value$attempt"* ]]; then
                    echo "   ✅ GET successful: $get_result"
                fi
                
                echo "✅ $config_name server is fully operational!"
                return 0
            else
                echo "   ⏳ PING not ready yet (got: '$ping_result')"
            fi
        else
            echo "   ⏳ Server process not found yet..."
        fi
        
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "❌ $config_name server failed to respond after $max_attempts attempts"
    echo "📋 Server logs:"
    if [[ "$config_name" == "4C" ]]; then
        tail -20 server_4c.log 2>/dev/null || echo "No 4C log found"
    else
        tail -20 server_12c.log 2>/dev/null || echo "No 12C log found"
    fi
    return 1
}

# Function to run quick benchmark
run_quick_benchmark() {
    local cores=$1
    local config_name=$2
    
    echo ""
    echo "🏃 QUICK BENCHMARK: $config_name"
    echo "================================="
    
    echo "📊 Quick performance test..."
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
        --clients=20 --threads=4 --pipeline=10 --data-size=64 \
        --key-pattern=R:R --ratio=1:3 --requests=50000 \
        --hide-histogram 2>/dev/null | grep -E "(Totals|Sets|Gets)" | head -3
    
    echo "✅ $config_name benchmark completed"
}

# Test 4C Configuration
echo "🧪 TESTING 4C 4S CONFIGURATION"
echo "==============================="

pkill -f meteor 2>/dev/null || true
sleep 3

echo "🚀 Starting 4C server..."
nohup ./meteor_1_2b_fixed_v1_restored -c 4 -s 4 > server_4c.log 2>&1 &
sleep 10  # Give it more time

if test_server_patient "4C"; then
    run_quick_benchmark 4 "4C"
    
    echo ""
    echo "🔍 4C Server Process Info:"
    ps aux | grep meteor | grep -v grep || echo "No meteor process found"
    
    echo ""
    echo "🔌 Network Connections:"
    netstat -an | grep :6379 || echo "No connections on port 6379"
else
    echo "❌ 4C server test failed"
fi

# Kill 4C server
pkill -f meteor 2>/dev/null || true
sleep 5

# Test 12C Configuration
echo ""
echo "🧪 TESTING 12C 12S CONFIGURATION" 
echo "================================="

echo "🚀 Starting 12C server..."
nohup ./meteor_1_2b_fixed_v1_restored -c 12 -s 12 > server_12c.log 2>&1 &
sleep 15  # Give it even more time

if test_server_patient "12C"; then
    run_quick_benchmark 12 "12C"
    
    echo ""
    echo "🔍 12C Server Process Info:"
    ps aux | grep meteor | grep -v grep || echo "No meteor process found"
    
    echo ""
    echo "🔌 Network Connections:"
    netstat -an | grep :6379 || echo "No connections on port 6379"
else
    echo "❌ 12C server test failed"
fi

# Cleanup
pkill -f meteor 2>/dev/null || true

echo ""
echo "🎯 PATIENT TESTING COMPLETE!"
echo "============================"
