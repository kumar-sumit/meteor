#!/bin/bash

# GCP Heavy Load Benchmark Script
# Tests Meteor vs Redis vs Dragonfly under heavy concurrent load
# Designed to reproduce and test fixes for crashes under heavy load

set -e

# Configuration
BENCHMARK_DATE=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="benchmark_results_${BENCHMARK_DATE}"
LOG_FILE="$RESULTS_DIR/benchmark.log"

# Test parameters - designed to stress test and reproduce crashes
HEAVY_LOAD_CONFIGS=(
    "50000:100:10"      # 50K requests, 100 clients, 10 pipeline
    "100000:200:20"     # 100K requests, 200 clients, 20 pipeline
    "200000:500:50"     # 200K requests, 500 clients, 50 pipeline (stress test)
    "500000:1000:100"   # 500K requests, 1000 clients, 100 pipeline (extreme load)
)

# Servers to test
SERVERS=(
    "redis:6379:redis-server"
    "dragonfly:6380:dragonfly"
    "meteor-v2:6381:./meteor-sharded-server-v2"
    "meteor-tiered:6382:./meteor-sharded-server-tiered"
)

# Create results directory
mkdir -p "$RESULTS_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if server is running
is_server_running() {
    local port=$1
    timeout 5 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null
}

# Function to wait for server to be ready
wait_for_server() {
    local port=$1
    local timeout=30
    local count=0
    
    while ! is_server_running $port && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
    done
    
    if [ $count -eq $timeout ]; then
        log "ERROR: Server on port $port did not start within $timeout seconds"
        return 1
    fi
    
    log "Server on port $port is ready"
    return 0
}

# Function to stop server
stop_server() {
    local port=$1
    local name=$2
    
    log "Stopping $name on port $port..."
    
    # Find and kill process by port
    local pid=$(lsof -ti:$port 2>/dev/null || echo "")
    if [ -n "$pid" ]; then
        kill -TERM $pid 2>/dev/null || true
        sleep 2
        kill -KILL $pid 2>/dev/null || true
    fi
    
    # Also kill by process name pattern
    pkill -f "$name" 2>/dev/null || true
    
    # Wait for port to be free
    local count=0
    while is_server_running $port && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done
}

# Function to start Redis
start_redis() {
    log "Starting Redis server..."
    redis-server --port 6379 --save "" --appendonly no --maxmemory 1gb --maxmemory-policy allkeys-lru --tcp-backlog 511 --timeout 0 --tcp-keepalive 300 --daemonize yes --logfile "$RESULTS_DIR/redis.log"
    wait_for_server 6379
}

# Function to start Dragonfly
start_dragonfly() {
    log "Starting Dragonfly server..."
    if [ -f "./dragonfly-aarch64" ]; then
        ./dragonfly-aarch64 --port=6380 --maxmemory=1gb --alsologtostderr --daemonize --logfile="$RESULTS_DIR/dragonfly.log" &
    else
        dragonfly --port=6380 --maxmemory=1gb --alsologtostderr --daemonize --logfile="$RESULTS_DIR/dragonfly.log" &
    fi
    wait_for_server 6380
}

# Function to start Meteor servers
start_meteor_v2() {
    log "Starting Meteor v2 server..."
    ./meteor-sharded-server-v2 --port 6381 --max-connections 10000 --enable-logging > "$RESULTS_DIR/meteor-v2.log" 2>&1 &
    wait_for_server 6381
}

start_meteor_tiered() {
    log "Starting Meteor tiered server..."
    ./meteor-sharded-server-tiered --port 6382 --hybrid-overflow /tmp/meteor-tiered --max-connections 10000 --enable-logging > "$RESULTS_DIR/meteor-tiered.log" 2>&1 &
    wait_for_server 6382
}

# Function to run benchmark
run_benchmark() {
    local server_name=$1
    local port=$2
    local requests=$3
    local clients=$4
    local pipeline=$5
    local test_name="$6"
    
    log "Running $test_name benchmark on $server_name (port $port)"
    log "Config: $requests requests, $clients clients, $pipeline pipeline"
    
    local output_file="$RESULTS_DIR/${server_name}_${test_name}_${requests}r_${clients}c_${pipeline}p.txt"
    
    # Run the benchmark with error handling
    if timeout 300 redis-benchmark -h localhost -p $port -n $requests -c $clients -P $pipeline -q --csv > "$output_file" 2>&1; then
        log "✅ $server_name $test_name benchmark completed successfully"
        
        # Extract key metrics
        local ops_per_sec=$(grep "SET" "$output_file" | cut -d',' -f2 | head -1)
        local get_ops_per_sec=$(grep "GET" "$output_file" | cut -d',' -f2 | head -1)
        
        log "   SET ops/sec: $ops_per_sec"
        log "   GET ops/sec: $get_ops_per_sec"
        
        return 0
    else
        log "❌ $server_name $test_name benchmark FAILED or CRASHED"
        
        # Check if server is still running
        if ! is_server_running $port; then
            log "🔥 CRASH DETECTED: $server_name server crashed during $test_name test"
            echo "CRASH,$server_name,$test_name,$requests,$clients,$pipeline" >> "$RESULTS_DIR/crash_summary.csv"
        fi
        
        return 1
    fi
}

# Function to run stress test
run_stress_test() {
    local server_name=$1
    local port=$2
    
    log "Running stress test on $server_name..."
    
    # Concurrent operations test
    local pids=()
    for i in {1..10}; do
        (
            for j in {1..1000}; do
                redis-cli -h localhost -p $port SET "stress_${i}_${j}" "value_${j}" > /dev/null 2>&1
                redis-cli -h localhost -p $port GET "stress_${i}_${j}" > /dev/null 2>&1
            done
        ) &
        pids+=($!)
    done
    
    # Wait for all background processes
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait $pid; then
            failed=1
        fi
    done
    
    if [ $failed -eq 0 ]; then
        log "✅ $server_name stress test completed successfully"
        return 0
    else
        log "❌ $server_name stress test FAILED"
        return 1
    fi
}

# Function to check server health
check_server_health() {
    local server_name=$1
    local port=$2
    
    log "Checking $server_name health..."
    
    # Basic connectivity
    if ! is_server_running $port; then
        log "❌ $server_name is not responding"
        return 1
    fi
    
    # PING test
    if timeout 5 redis-cli -h localhost -p $port ping > /dev/null 2>&1; then
        log "✅ $server_name PING successful"
    else
        log "❌ $server_name PING failed"
        return 1
    fi
    
    # Memory test
    if timeout 5 redis-cli -h localhost -p $port set health_check "test_value" > /dev/null 2>&1; then
        log "✅ $server_name SET successful"
    else
        log "❌ $server_name SET failed"
        return 1
    fi
    
    if timeout 5 redis-cli -h localhost -p $port get health_check > /dev/null 2>&1; then
        log "✅ $server_name GET successful"
    else
        log "❌ $server_name GET failed"
        return 1
    fi
    
    return 0
}

# Main benchmark function
run_server_benchmarks() {
    local server_info=$1
    IFS=':' read -r server_name port start_command <<< "$server_info"
    
    log "=========================================="
    log "Testing $server_name"
    log "=========================================="
    
    # Stop any existing server
    stop_server $port $server_name
    sleep 2
    
    # Start server
    case $server_name in
        "redis")
            start_redis
            ;;
        "dragonfly")
            start_dragonfly
            ;;
        "meteor-v2")
            start_meteor_v2
            ;;
        "meteor-tiered")
            start_meteor_tiered
            ;;
        *)
            log "Unknown server: $server_name"
            return 1
            ;;
    esac
    
    # Check initial health
    if ! check_server_health $server_name $port; then
        log "❌ $server_name failed initial health check"
        return 1
    fi
    
    # Run benchmarks with increasing load
    local test_count=0
    local crash_count=0
    
    for config in "${HEAVY_LOAD_CONFIGS[@]}"; do
        IFS=':' read -r requests clients pipeline <<< "$config"
        
        log "Running heavy load test: $requests requests, $clients clients, $pipeline pipeline"
        
        if run_benchmark $server_name $port $requests $clients $pipeline "heavy_load_${test_count}"; then
            log "✅ Heavy load test $test_count passed"
        else
            log "❌ Heavy load test $test_count failed"
            crash_count=$((crash_count + 1))
            
            # Check if server crashed
            if ! is_server_running $port; then
                log "🔥 Server crashed! Attempting restart..."
                
                # Try to restart server
                case $server_name in
                    "redis")
                        start_redis
                        ;;
                    "dragonfly")
                        start_dragonfly
                        ;;
                    "meteor-v2")
                        start_meteor_v2
                        ;;
                    "meteor-tiered")
                        start_meteor_tiered
                        ;;
                esac
                
                if ! wait_for_server $port; then
                    log "❌ Failed to restart $server_name"
                    return 1
                fi
            fi
        fi
        
        test_count=$((test_count + 1))
        
        # Brief pause between tests
        sleep 5
    done
    
    # Run stress test
    if run_stress_test $server_name $port; then
        log "✅ Stress test passed"
    else
        log "❌ Stress test failed"
        crash_count=$((crash_count + 1))
    fi
    
    # Final health check
    if check_server_health $server_name $port; then
        log "✅ Final health check passed"
    else
        log "❌ Final health check failed"
        crash_count=$((crash_count + 1))
    fi
    
    # Stop server
    stop_server $port $server_name
    
    log "$server_name testing completed. Crashes: $crash_count"
    echo "$server_name,$crash_count" >> "$RESULTS_DIR/crash_summary.csv"
    
    return 0
}

# Main execution
main() {
    log "Starting GCP Heavy Load Benchmark"
    log "Results will be saved to: $RESULTS_DIR"
    
    # System information
    log "System Information:"
    log "  OS: $(uname -a)"
    log "  CPU: $(nproc) cores"
    log "  Memory: $(free -h | grep Mem | awk '{print $2}')"
    log "  Disk: $(df -h / | tail -1 | awk '{print $4}' | sed 's/G/ GB/')"
    
    # Initialize crash summary
    echo "Server,Crashes" > "$RESULTS_DIR/crash_summary.csv"
    
    # Build servers if needed
    if [ ! -f "./meteor-sharded-server-v2" ]; then
        log "Building Meteor v2 server..."
        go build -o meteor-sharded-server-v2 ./cmd/server-sharded/
    fi
    
    if [ ! -f "./meteor-sharded-server-tiered" ]; then
        log "Building Meteor tiered server..."
        go build -o meteor-sharded-server-tiered ./cmd/server-sharded/
    fi
    
    # Run benchmarks for each server
    for server_info in "${SERVERS[@]}"; do
        run_server_benchmarks "$server_info"
        sleep 10  # Pause between servers
    done
    
    # Generate summary report
    log "=========================================="
    log "BENCHMARK SUMMARY"
    log "=========================================="
    
    log "Crash Summary:"
    cat "$RESULTS_DIR/crash_summary.csv" | tee -a "$LOG_FILE"
    
    # Performance comparison
    log "Performance Comparison (SET ops/sec):"
    for server_info in "${SERVERS[@]}"; do
        IFS=':' read -r server_name port start_command <<< "$server_info"
        local best_result=$(find "$RESULTS_DIR" -name "${server_name}_*.txt" -exec grep "SET" {} \; | cut -d',' -f2 | sort -nr | head -1)
        if [ -n "$best_result" ]; then
            log "  $server_name: $best_result ops/sec"
        else
            log "  $server_name: No results (crashed)"
        fi
    done
    
    log "Benchmark completed. Results saved to: $RESULTS_DIR"
    log "To deploy to GCP VM, run: scp -r $RESULTS_DIR user@gcp-vm-ip:~/"
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    for server_info in "${SERVERS[@]}"; do
        IFS=':' read -r server_name port start_command <<< "$server_info"
        stop_server $port $server_name
    done
}

# Set up signal handlers
trap cleanup EXIT

# Run main function
main "$@" 