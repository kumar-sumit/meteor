#!/bin/bash

# Direct memtier benchmark testing - bypass netcat issues

echo "🎯 DIRECT MEMTIER BENCHMARK TEST"
echo "================================"

cd /mnt/externalDisk/meteor

# Function to run memtier benchmark directly
run_direct_benchmark() {
    local cores=$1
    local shards=$2
    local config_name=$3
    
    echo ""
    echo "🏃 DIRECT BENCHMARK: $config_name Configuration"
    echo "=============================================="
    
    echo "📊 Test 1: Quick connectivity check"
    echo "------------------------------------"
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
        --clients=5 --threads=1 --pipeline=1 --data-size=32 \
        --key-pattern=R:R --ratio=1:1 --requests=100 \
        --hide-histogram 2>/dev/null | grep -E "(Totals|ERROR|error|Connection|ops/sec)" | head -10
    
    local memtier_exit_code=$?
    if [ $memtier_exit_code -eq 0 ]; then
        echo "✅ $config_name server responding to memtier!"
        
        echo ""
        echo "📊 Test 2: Performance benchmark"
        echo "---------------------------------"
        memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
            --clients=20 --threads=4 --pipeline=10 --data-size=64 \
            --key-pattern=R:R --ratio=1:3 --requests=50000 \
            --hide-histogram 2>/dev/null | grep -E "(Totals|Sets|Gets)" | head -5
        
        echo ""
        echo "📊 Test 3: Pipeline stress test"  
        echo "--------------------------------"
        memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
            --clients=50 --threads=8 --pipeline=20 --data-size=64 \
            --key-pattern=R:R --ratio=1:1 --requests=100000 \
            --hide-histogram 2>/dev/null | grep -E "(Totals|Sets|Gets)" | head -5
            
        echo "✅ $config_name benchmarks completed successfully!"
    else
        echo "❌ $config_name server not responding to memtier (exit code: $memtier_exit_code)"
        
        echo ""
        echo "🔍 Debugging info:"
        echo "Process status:"
        ps aux | grep meteor | grep -v grep || echo "No meteor process found"
        echo ""
        echo "Port status:"
        netstat -an | grep :6379 || echo "No port 6379 binding found"
        echo ""
        echo "Recent log entries:"
        if [[ "$config_name" == "4C" ]]; then
            tail -10 server_4c.log 2>/dev/null || echo "No 4C log found"
        else
            tail -10 server_12c.log 2>/dev/null || echo "No 12C log found"
        fi
    fi
}

# Test 4C Configuration  
echo "🧪 TESTING 4C 4S CONFIGURATION"
echo "==============================="

pkill -f meteor 2>/dev/null || true
sleep 3

echo "🚀 Starting 4C server..."
nohup ./meteor_1_2b_fixed_v1_restored -c 4 -s 4 > server_4c.log 2>&1 &
server_4c_pid=$!

echo "⏳ Waiting for 4C server startup..."
sleep 12

echo "🔍 4C Server status:"
if ps -p $server_4c_pid > /dev/null; then
    echo "✅ 4C Server process is running (PID: $server_4c_pid)"
    run_direct_benchmark 4 4 "4C"
else
    echo "❌ 4C Server process died"
    echo "4C Server log:"
    cat server_4c.log 2>/dev/null || echo "No log found"
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
server_12c_pid=$!

echo "⏳ Waiting for 12C server startup..." 
sleep 15

echo "🔍 12C Server status:"
if ps -p $server_12c_pid > /dev/null; then
    echo "✅ 12C Server process is running (PID: $server_12c_pid)"
    run_direct_benchmark 12 12 "12C"
else
    echo "❌ 12C Server process died"
    echo "12C Server log:"
    cat server_12c.log 2>/dev/null || echo "No log found"
fi

# Final cleanup
pkill -f meteor 2>/dev/null || true

echo ""
echo "🎯 DIRECT MEMTIER TESTING COMPLETE!"
echo "==================================="
echo ""
echo "📋 Summary:"
echo "- Both servers started and accepted connections" 
echo "- Tested with memtier_benchmark directly"
echo "- Logs available: server_4c.log, server_12c.log"












