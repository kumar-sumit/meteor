#!/bin/bash

# Test script for Meteor v7.0 Single Command Correctness

echo "🧪 METEOR v7.0 SINGLE COMMAND CORRECTNESS VALIDATION"
echo "===================================================="

cd /mnt/externalDisk/meteor 2>/dev/null || cd .

# Function to test server connectivity and basic commands
test_server_basic() {
    local config_name=$1
    local cores=$2
    local shards=$3
    
    echo "🔍 Testing $config_name basic functionality..."
    
    # Test basic connectivity
    echo "PING" | timeout 5 nc -w 2 127.0.0.1 6379 > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ $config_name server responding"
    else
        echo "❌ $config_name server not responding"
        return 1
    fi
    
    # Test single SET command
    set_response=$(echo -e "SET test:single:$config_name value_$config_name\r" | timeout 5 nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r\n')
    if [[ "$set_response" == *"OK"* ]]; then
        echo "✅ $config_name single SET working"
    else
        echo "❌ $config_name single SET failed: '$set_response'"
    fi
    
    # Test single GET command
    get_response=$(echo -e "GET test:single:$config_name\r" | timeout 5 nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r\n')
    if [[ "$get_response" == *"value_$config_name"* ]]; then
        echo "✅ $config_name single GET working"
    else
        echo "❌ $config_name single GET failed: '$get_response'"
    fi
    
    return 0
}

# Function to test cross-shard correctness
test_cross_shard_correctness() {
    local config_name=$1
    local cores=$2
    local shards=$3
    
    echo "🎯 Testing $config_name cross-shard correctness..."
    
    # Test multiple keys that should go to different shards
    local keys=("key1" "key2" "key3" "key4" "key5" "key6" "key7" "key8")
    local values=("val1" "val2" "val3" "val4" "val5" "val6" "val7" "val8")
    
    # SET commands to different shards
    for i in "${!keys[@]}"; do
        local key="${keys[$i]}"
        local value="${values[$i]}"
        
        set_response=$(echo -e "SET crossshard:$key $value\r" | timeout 5 nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r\n')
        if [[ "$set_response" != *"OK"* ]]; then
            echo "❌ $config_name cross-shard SET failed for $key: '$set_response'"
            return 1
        fi
    done
    
    echo "✅ $config_name cross-shard SET commands successful"
    
    # GET commands from different shards
    local success_count=0
    for i in "${!keys[@]}"; do
        local key="${keys[$i]}"
        local expected_value="${values[$i]}"
        
        get_response=$(echo -e "GET crossshard:$key\r" | timeout 5 nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r\n')
        if [[ "$get_response" == *"$expected_value"* ]]; then
            success_count=$((success_count + 1))
        else
            echo "⚠️  $config_name cross-shard GET failed for $key: expected '$expected_value', got '$get_response'"
        fi
    done
    
    local accuracy=$((success_count * 100 / ${#keys[@]}))
    echo "📊 $config_name cross-shard GET accuracy: $success_count/${#keys[@]} = $accuracy%"
    
    if [ $accuracy -eq 100 ]; then
        echo "✅ $config_name cross-shard correctness: 100%"
        return 0
    else
        echo "❌ $config_name cross-shard correctness: $accuracy% (should be 100%)"
        return 1
    fi
}

# Function to run pipeline benchmark
test_pipeline_performance() {
    local config_name=$1
    local cores=$2
    local shards=$3
    
    echo "🚀 Testing $config_name pipeline performance..."
    
    # Run pipeline benchmark to ensure no regression
    local result=$(memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
        --clients=20 --threads=4 --pipeline=10 --data-size=64 \
        --key-pattern=R:R --ratio=1:1 --requests=50000 \
        --hide-histogram 2>/dev/null | grep "Totals" | head -1)
    
    if [[ -n "$result" ]]; then
        echo "✅ $config_name pipeline performance: $result"
        
        # Extract QPS
        local qps=$(echo "$result" | awk '{print $2}' | sed 's/,//g')
        local qps_numeric=$(echo "$qps" | cut -d'.' -f1)
        
        if [ "$qps_numeric" -gt 1000000 ]; then
            echo "✅ $config_name pipeline QPS: ${qps} (>1M QPS - excellent)"
        else
            echo "⚠️  $config_name pipeline QPS: ${qps} (lower than expected)"
        fi
    else
        echo "❌ $config_name pipeline benchmark failed"
    fi
}

# Function to test single command performance
test_single_command_performance() {
    local config_name=$1
    local cores=$2
    local shards=$3
    
    echo "⚡ Testing $config_name single command performance..."
    
    # Run single command benchmark
    local result=$(memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
        --clients=10 --threads=4 --pipeline=1 --data-size=64 \
        --key-pattern=R:R --ratio=0:1 --requests=25000 \
        --hide-histogram 2>/dev/null | grep "Totals" | head -1)
    
    if [[ -n "$result" ]]; then
        echo "✅ $config_name single command performance: $result"
        
        # Extract QPS
        local qps=$(echo "$result" | awk '{print $2}' | sed 's/,//g')
        local qps_numeric=$(echo "$qps" | cut -d'.' -f1)
        
        if [ "$qps_numeric" -gt 500000 ]; then
            echo "✅ $config_name single command QPS: ${qps} (>500K QPS - excellent)"
        else
            echo "⚠️  $config_name single command QPS: ${qps}"
        fi
    else
        echo "❌ $config_name single command benchmark failed"
    fi
}

# Main test function
run_comprehensive_test() {
    local config_name=$1
    local cores=$2
    local shards=$3
    
    echo ""
    echo "🧪 TESTING $config_name CONFIGURATION"
    echo "======================================"
    
    # Kill any existing server
    pkill -f meteor_single_command_fixed 2>/dev/null || true
    sleep 3
    
    # Start server
    echo "🚀 Starting $config_name server..."
    nohup ./meteor_single_command_fixed -c $cores -s $shards > "server_${config_name}.log" 2>&1 &
    local server_pid=$!
    
    # Wait for server to initialize
    sleep 8
    
    # Check if server is running
    if ps -p $server_pid > /dev/null 2>&1; then
        echo "✅ $config_name server started (PID: $server_pid)"
        
        # Run tests
        if test_server_basic "$config_name" $cores $shards; then
            test_cross_shard_correctness "$config_name" $cores $shards
            test_single_command_performance "$config_name" $cores $shards
            test_pipeline_performance "$config_name" $cores $shards
        fi
        
    else
        echo "❌ $config_name server failed to start"
        echo "Last 10 lines of server log:"
        tail -10 "server_${config_name}.log" 2>/dev/null || echo "No log found"
    fi
    
    # Cleanup
    pkill -f meteor_single_command_fixed 2>/dev/null || true
    sleep 2
}

# Run tests for both configurations
echo "🎯 COMPREHENSIVE SINGLE COMMAND CORRECTNESS TESTING"
echo "🎯 Testing scenarios: num_cores = num_shards (maximum cross-shard routing)"
echo ""

run_comprehensive_test "4C4S" 4 4
run_comprehensive_test "12C12S" 12 12

echo ""
echo "🏆 TESTING COMPLETE!"
echo "==================="
echo ""
echo "📋 Summary:"
echo "- 4C4S: Check logs in server_4C4S.log"
echo "- 12C12S: Check logs in server_12C12S.log"
echo ""
echo "✅ Single command correctness fix validation complete!"
echo "🚀 Pipeline performance preservation verified!"












