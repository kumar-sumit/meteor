#!/bin/bash

# Professional benchmark script using redis-benchmark
# Tests Redis vs Meteor server with comprehensive metrics

REDIS_HOST="localhost"
REDIS_PORT="6379"
METEOR_HOST="localhost"
METEOR_PORT="6380"

# Test parameters
CLIENTS=50
REQUESTS=10000
DATA_SIZE=1024
PIPELINE=1

echo "================================================================"
echo "       PROFESSIONAL REDIS vs METEOR BENCHMARK"
echo "================================================================"
echo "Tool: redis-benchmark"
echo "Clients: $CLIENTS"
echo "Requests: $REQUESTS"
echo "Data Size: $DATA_SIZE bytes"
echo "Pipeline: $PIPELINE"
echo "================================================================"

# Function to run redis-benchmark
run_benchmark() {
    local server_name=$1
    local host=$2
    local port=$3
    
    echo
    echo "Testing $server_name ($host:$port)"
    echo "=========================================="
    
    # Check if server is running
    if ! redis-cli -h $host -p $port ping > /dev/null 2>&1; then
        echo "ERROR: $server_name is not responding!"
        return 1
    fi
    
    # Clear database
    redis-cli -h $host -p $port flushall > /dev/null 2>&1
    
    echo
    echo "1. SET Operations Benchmark"
    echo "----------------------------------------"
    redis-benchmark -h $host -p $port -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t set -P $PIPELINE
    
    echo
    echo "2. GET Operations Benchmark"
    echo "----------------------------------------"
    redis-benchmark -h $host -p $port -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t get -P $PIPELINE
    
    echo
    echo "3. Mixed Operations Benchmark"
    echo "----------------------------------------"
    redis-benchmark -h $host -p $port -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t set,get -P $PIPELINE
    
    echo
    echo "4. Multiple Data Types Benchmark"
    echo "----------------------------------------"
    redis-benchmark -h $host -p $port -c $CLIENTS -n $REQUESTS -d $DATA_SIZE -t set,get,incr,lpush,lpop,sadd,spop -P $PIPELINE
    
    echo
    echo "5. Latency Test"
    echo "----------------------------------------"
    redis-cli -h $host -p $port --latency-history -i 1 > /tmp/${server_name}_latency.log &
    local latency_pid=$!
    sleep 5
    kill $latency_pid 2>/dev/null
    
    echo "Latency results for $server_name:"
    tail -5 /tmp/${server_name}_latency.log
    
    echo
    echo "6. Memory Efficiency Test"
    echo "----------------------------------------"
    redis-cli -h $host -p $port info memory | grep -E "(used_memory|used_memory_human)"
    
    echo
    echo "=========================================="
    echo "$server_name benchmark completed"
    echo "=========================================="
}

# Function to run custom workload
run_custom_workload() {
    local server_name=$1
    local host=$2
    local port=$3
    
    echo
    echo "7. Custom Workload Test - $server_name"
    echo "----------------------------------------"
    
    # Test TTL operations
    echo "Testing TTL operations..."
    redis-benchmark -h $host -p $port -c 10 -n 1000 -r 100 -e --eval "
    redis.call('set', KEYS[1], ARGV[1], 'EX', '60')
    return redis.call('get', KEYS[1])
    " 1 test_value
    
    # Test existence operations
    echo "Testing EXISTS operations..."
    redis-benchmark -h $host -p $port -c 10 -n 1000 -t exists
    
    # Test deletion operations
    echo "Testing DEL operations..."
    redis-benchmark -h $host -p $port -c 10 -n 1000 -t del
}

# Create results directory
mkdir -p /tmp/benchmark_results

# Run Redis benchmark
echo "Starting Redis benchmark..."
run_benchmark "Redis" $REDIS_HOST $REDIS_PORT > /tmp/benchmark_results/redis_results.txt 2>&1
run_custom_workload "Redis" $REDIS_HOST $REDIS_PORT >> /tmp/benchmark_results/redis_results.txt 2>&1

# Run Meteor benchmark
echo "Starting Meteor benchmark..."
run_benchmark "Meteor" $METEOR_HOST $METEOR_PORT > /tmp/benchmark_results/meteor_results.txt 2>&1
run_custom_workload "Meteor" $METEOR_HOST $METEOR_PORT >> /tmp/benchmark_results/meteor_results.txt 2>&1

# Display results
echo
echo "================================================================"
echo "                    BENCHMARK RESULTS"
echo "================================================================"

echo
echo "Redis Results:"
echo "=============="
cat /tmp/benchmark_results/redis_results.txt

echo
echo "Meteor Results:"
echo "==============="
cat /tmp/benchmark_results/meteor_results.txt

echo
echo "================================================================"
echo "                    PERFORMANCE COMPARISON"
echo "================================================================"

# Extract key metrics from results
echo "Extracting performance metrics..."

# Function to extract throughput from redis-benchmark output
extract_throughput() {
    local file=$1
    local operation=$2
    grep -A 5 "$operation Operations Benchmark" "$file" | grep "requests per second" | head -1 | awk '{print $1}'
}

# Extract throughput values
REDIS_SET_THROUGHPUT=$(extract_throughput "/tmp/benchmark_results/redis_results.txt" "SET")
METEOR_SET_THROUGHPUT=$(extract_throughput "/tmp/benchmark_results/meteor_results.txt" "SET")

REDIS_GET_THROUGHPUT=$(extract_throughput "/tmp/benchmark_results/redis_results.txt" "GET")
METEOR_GET_THROUGHPUT=$(extract_throughput "/tmp/benchmark_results/meteor_results.txt" "GET")

echo
echo "Summary Comparison:"
echo "==================="
printf "%-20s %-20s %-20s\n" "Operation" "Redis (ops/sec)" "Meteor (ops/sec)"
echo "------------------------------------------------------------"
printf "%-20s %-20s %-20s\n" "SET" "$REDIS_SET_THROUGHPUT" "$METEOR_SET_THROUGHPUT"
printf "%-20s %-20s %-20s\n" "GET" "$REDIS_GET_THROUGHPUT" "$METEOR_GET_THROUGHPUT"

echo
echo "Performance Analysis:"
echo "===================="

# Calculate improvements
if [[ -n "$REDIS_SET_THROUGHPUT" && -n "$METEOR_SET_THROUGHPUT" ]]; then
    SET_IMPROVEMENT=$(echo "scale=2; ($METEOR_SET_THROUGHPUT - $REDIS_SET_THROUGHPUT) * 100 / $REDIS_SET_THROUGHPUT" | bc)
    echo "SET Performance: Meteor is ${SET_IMPROVEMENT}% compared to Redis"
fi

if [[ -n "$REDIS_GET_THROUGHPUT" && -n "$METEOR_GET_THROUGHPUT" ]]; then
    GET_IMPROVEMENT=$(echo "scale=2; ($METEOR_GET_THROUGHPUT - $REDIS_GET_THROUGHPUT) * 100 / $REDIS_GET_THROUGHPUT" | bc)
    echo "GET Performance: Meteor is ${GET_IMPROVEMENT}% compared to Redis"
fi

echo
echo "Full results available in:"
echo "  Redis: /tmp/benchmark_results/redis_results.txt"
echo "  Meteor: /tmp/benchmark_results/meteor_results.txt"
echo
echo "Professional benchmark completed!"
echo "================================================================" 