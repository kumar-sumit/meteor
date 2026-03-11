#!/bin/bash

# Comprehensive Test Script for meteor_1_2b_fixed_v1_restored
# Tests both 4C 4S and 12C 12S configurations

echo "🚀 COMPREHENSIVE BENCHMARK: meteor_1_2b_fixed_v1_restored"
echo "======================================================="

cd /mnt/externalDisk/meteor

# Kill any existing meteor processes
pkill -f meteor 2>/dev/null || true
sleep 2

# Function to test server connectivity
test_connectivity() {
    local config_name=$1
    echo "🔍 Testing $config_name connectivity..."
    
    # Test PING
    ping_result=$(echo -e "PING\r" | timeout 3 nc -w 1 127.0.0.1 6379 2>/dev/null | head -1)
    if [[ "$ping_result" == *"PONG"* ]]; then
        echo "✅ PING successful"
    else
        echo "❌ PING failed"
        return 1
    fi
    
    # Test SET/GET
    set_get_result=$(echo -e "SET test:key hello\r\nGET test:key\r" | timeout 3 nc -w 1 127.0.0.1 6379 2>/dev/null)
    if [[ "$set_get_result" == *"OK"* ]] && [[ "$set_get_result" == *"hello"* ]]; then
        echo "✅ SET/GET successful"
    else
        echo "❌ SET/GET failed"
        return 1
    fi
    
    echo "✅ $config_name server is responding correctly"
    return 0
}

# Function to run benchmark
run_benchmark() {
    local cores=$1
    local shards=$2
    local config_name=$3
    
    echo ""
    echo "🏃 BENCHMARK: $config_name Configuration"
    echo "=========================================="
    
    # Multiple benchmark scenarios
    echo "📊 Scenario 1: High-throughput with medium pipeline"
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
        --clients=50 --threads=8 --pipeline=10 --data-size=64 \
        --key-pattern=R:R --ratio=1:3 --requests=100000 \
        --hide-histogram | grep -E "(Totals|Sets|Gets)" | head -3
    
    echo ""
    echo "📊 Scenario 2: Maximum pipeline stress test"
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
        --clients=100 --threads=12 --pipeline=20 --data-size=64 \
        --key-pattern=R:R --ratio=1:1 --requests=200000 \
        --hide-histogram | grep -E "(Totals|Sets|Gets)" | head -3
    
    echo ""
    echo "📊 Scenario 3: Cross-shard heavy workload"
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
        --clients=80 --threads=10 --pipeline=15 --data-size=128 \
        --key-pattern=G:G --ratio=1:5 --requests=150000 \
        --hide-histogram | grep -E "(Totals|Sets|Gets)" | head -3
    
    echo ""
}

# Test 4C 4S Configuration
echo "🧪 TESTING 4C 4S CONFIGURATION"
echo "==============================="

echo "🚀 Starting meteor_1_2b_fixed_v1_restored in 4C 4S mode..."
nohup ./meteor_1_2b_fixed_v1_restored -c 4 -s 4 > server_4c.log 2>&1 &
sleep 8

if test_connectivity "4C 4S"; then
    run_benchmark 4 4 "4C 4S"
else
    echo "❌ 4C server failed to start properly"
    cat server_4c.log | tail -10
fi

# Kill 4C server before starting 12C
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "🧪 TESTING 12C 12S CONFIGURATION"
echo "================================="

echo "🚀 Starting meteor_1_2b_fixed_v1_restored in 12C 12S mode..."
nohup ./meteor_1_2b_fixed_v1_restored -c 12 -s 12 > server_12c.log 2>&1 &
sleep 10

if test_connectivity "12C 12S"; then
    run_benchmark 12 12 "12C 12S"
else
    echo "❌ 12C server failed to start properly"
    cat server_12c.log | tail -10
fi

# Cleanup
pkill -f meteor 2>/dev/null || true

echo ""
echo "🎯 BENCHMARK COMPLETE!"
echo "======================"
echo "📋 Results Summary:"
echo "- 4C 4S Log: server_4c.log"  
echo "- 12C 12S Log: server_12c.log"
echo ""
echo "✅ meteor_1_2b_fixed_v1_restored tested in both configurations"












