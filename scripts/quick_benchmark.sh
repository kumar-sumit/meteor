#!/bin/bash

# Quick benchmark script for Redis vs Meteor server
# Reduced operations for faster results

REDIS_HOST="localhost"
REDIS_PORT="6379"
METEOR_HOST="localhost"
METEOR_PORT="6380"

# Test parameters (reduced for speed)
SET_OPERATIONS=1000
GET_OPERATIONS=1000
CONCURRENT_CLIENTS=5
VALUE_SIZE=1024

echo "================================================================"
echo "          REDIS vs METEOR SERVER QUICK BENCHMARK"
echo "================================================================"
echo "SET Operations: ${SET_OPERATIONS}"
echo "GET Operations: ${GET_OPERATIONS}"
echo "Concurrent Clients: ${CONCURRENT_CLIENTS}"
echo "Value Size: ${VALUE_SIZE} bytes"
echo "================================================================"

# Function to test server performance
test_server_performance() {
    local server_name=$1
    local host=$2
    local port=$3
    
    echo
    echo "Testing $server_name ($host:$port)"
    echo "----------------------------------------"
    
    # Check if server is running
    if ! redis-cli -h $host -p $port ping > /dev/null 2>&1; then
        echo "ERROR: $server_name is not responding!"
        return 1
    fi
    
    # Clear the database
    redis-cli -h $host -p $port flushall > /dev/null 2>&1
    
    # Test 1: SET Performance
    echo "1. SET Performance Test..."
    local start_time=$(date +%s%N)
    for i in $(seq 1 $SET_OPERATIONS); do
        redis-cli -h $host -p $port set "key_$i" "test_value_$i" > /dev/null 2>&1
    done
    local end_time=$(date +%s%N)
    local duration_ms=$(( ($end_time - $start_time) / 1000000 ))
    local set_ops_per_sec=$(( $SET_OPERATIONS * 1000 / $duration_ms ))
    
    echo "   SET Operations: $SET_OPERATIONS"
    echo "   Duration: ${duration_ms}ms"
    echo "   Throughput: ${set_ops_per_sec} ops/sec"
    echo "   Average Latency: $(( $duration_ms * 1000 / $SET_OPERATIONS ))μs"
    
    # Test 2: GET Performance
    echo "2. GET Performance Test..."
    local start_time=$(date +%s%N)
    for i in $(seq 1 $GET_OPERATIONS); do
        redis-cli -h $host -p $port get "key_$i" > /dev/null 2>&1
    done
    local end_time=$(date +%s%N)
    local duration_ms=$(( ($end_time - $start_time) / 1000000 ))
    local get_ops_per_sec=$(( $GET_OPERATIONS * 1000 / $duration_ms ))
    
    echo "   GET Operations: $GET_OPERATIONS"
    echo "   Duration: ${duration_ms}ms"
    echo "   Throughput: ${get_ops_per_sec} ops/sec"
    echo "   Average Latency: $(( $duration_ms * 1000 / $GET_OPERATIONS ))μs"
    
    # Test 3: Mixed Workload (reduced)
    echo "3. Mixed Workload Test (70% READ, 30% WRITE)..."
    local start_time=$(date +%s%N)
    for i in $(seq 1 100); do
        # 70% reads
        for j in $(seq 1 7); do
            local key_id=$((($i * 7 + $j) % $SET_OPERATIONS + 1))
            redis-cli -h $host -p $port get "key_$key_id" > /dev/null 2>&1
        done
        # 30% writes
        for j in $(seq 1 3); do
            local key_id=$(($i * 3 + $j + $SET_OPERATIONS))
            redis-cli -h $host -p $port set "key_$key_id" "mixed_value_$key_id" > /dev/null 2>&1
        done
    done
    local end_time=$(date +%s%N)
    local duration_ms=$(( ($end_time - $start_time) / 1000000 ))
    local mixed_ops_per_sec=$(( 1000 * 1000 / $duration_ms ))
    
    echo "   Mixed Operations: 1000 (700 GET, 300 SET)"
    echo "   Duration: ${duration_ms}ms"
    echo "   Throughput: ${mixed_ops_per_sec} ops/sec"
    echo "   Average Latency: $(( $duration_ms * 1000 / 1000 ))μs"
    
    # Test 4: Latency Test (50 operations)
    echo "4. Latency Distribution Test..."
    local latencies=()
    for i in $(seq 1 50); do
        local start_time=$(date +%s%N)
        redis-cli -h $host -p $port get "key_$i" > /dev/null 2>&1
        local end_time=$(date +%s%N)
        local latency=$(( ($end_time - $start_time) / 1000 ))
        latencies+=($latency)
    done
    
    # Calculate percentiles
    IFS=$'\n' sorted_latencies=($(sort -n <<<"${latencies[*]}"))
    local p50=${sorted_latencies[24]}
    local p95=${sorted_latencies[47]}
    local p99=${sorted_latencies[49]}
    local max_latency=${sorted_latencies[49]}
    
    echo "   P50 Latency: ${p50}μs"
    echo "   P95 Latency: ${p95}μs"
    echo "   P99 Latency: ${p99}μs"
    echo "   Max Latency: ${max_latency}μs"
    
    # Store results for comparison
    if [ "$server_name" == "Redis" ]; then
        REDIS_SET_OPS=$set_ops_per_sec
        REDIS_GET_OPS=$get_ops_per_sec
        REDIS_MIXED_OPS=$mixed_ops_per_sec
        REDIS_P50=$p50
        REDIS_P95=$p95
        REDIS_P99=$p99
    else
        METEOR_SET_OPS=$set_ops_per_sec
        METEOR_GET_OPS=$get_ops_per_sec
        METEOR_MIXED_OPS=$mixed_ops_per_sec
        METEOR_P50=$p50
        METEOR_P95=$p95
        METEOR_P99=$p99
    fi
}

# Start Redis server benchmark
echo "Starting Redis server benchmark..."
test_server_performance "Redis" $REDIS_HOST $REDIS_PORT

# Start Meteor server benchmark
echo
echo "Starting Meteor server benchmark..."
test_server_performance "Meteor" $METEOR_HOST $METEOR_PORT

# Summary comparison
echo
echo "================================================================"
echo "                    BENCHMARK RESULTS"
echo "================================================================"
echo
printf "%-20s %-15s %-15s %-15s\n" "Metric" "Redis" "Meteor" "Improvement"
echo "----------------------------------------------------------------"
printf "%-20s %-15s %-15s %-15s\n" "SET ops/sec" "$REDIS_SET_OPS" "$METEOR_SET_OPS" "$(( $METEOR_SET_OPS * 100 / $REDIS_SET_OPS - 100 ))%"
printf "%-20s %-15s %-15s %-15s\n" "GET ops/sec" "$REDIS_GET_OPS" "$METEOR_GET_OPS" "$(( $METEOR_GET_OPS * 100 / $REDIS_GET_OPS - 100 ))%"
printf "%-20s %-15s %-15s %-15s\n" "Mixed ops/sec" "$REDIS_MIXED_OPS" "$METEOR_MIXED_OPS" "$(( $METEOR_MIXED_OPS * 100 / $REDIS_MIXED_OPS - 100 ))%"
echo "----------------------------------------------------------------"
printf "%-20s %-15s %-15s %-15s\n" "P50 Latency (μs)" "$REDIS_P50" "$METEOR_P50" "$(( ($REDIS_P50 - $METEOR_P50) * 100 / $REDIS_P50 ))% faster"
printf "%-20s %-15s %-15s %-15s\n" "P95 Latency (μs)" "$REDIS_P95" "$METEOR_P95" "$(( ($REDIS_P95 - $METEOR_P95) * 100 / $REDIS_P95 ))% faster"
printf "%-20s %-15s %-15s %-15s\n" "P99 Latency (μs)" "$REDIS_P99" "$METEOR_P99" "$(( ($REDIS_P99 - $METEOR_P99) * 100 / $REDIS_P99 ))% faster"
echo "================================================================"

# Performance summary
echo
echo "PERFORMANCE SUMMARY:"
if [ $METEOR_SET_OPS -gt $REDIS_SET_OPS ]; then
    echo "✅ Meteor SET operations are $(( ($METEOR_SET_OPS - $REDIS_SET_OPS) * 100 / $REDIS_SET_OPS ))% faster than Redis"
else
    echo "❌ Redis SET operations are $(( ($REDIS_SET_OPS - $METEOR_SET_OPS) * 100 / $METEOR_SET_OPS ))% faster than Meteor"
fi

if [ $METEOR_GET_OPS -gt $REDIS_GET_OPS ]; then
    echo "✅ Meteor GET operations are $(( ($METEOR_GET_OPS - $REDIS_GET_OPS) * 100 / $REDIS_GET_OPS ))% faster than Redis"
else
    echo "❌ Redis GET operations are $(( ($REDIS_GET_OPS - $METEOR_GET_OPS) * 100 / $METEOR_GET_OPS ))% faster than Meteor"
fi

if [ $METEOR_P50 -lt $REDIS_P50 ]; then
    echo "✅ Meteor P50 latency is $(( ($REDIS_P50 - $METEOR_P50) * 100 / $REDIS_P50 ))% better than Redis"
else
    echo "❌ Redis P50 latency is $(( ($METEOR_P50 - $REDIS_P50) * 100 / $METEOR_P50 ))% better than Meteor"
fi

echo
echo "Quick benchmark completed!"
echo "================================================================" 