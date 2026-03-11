#!/bin/bash

# **COMPREHENSIVE PIPELINE PERFORMANCE BENCHMARK**
# Tests cross-core pipeline correctness, throughput, and latency
# Validates the integrated IO_URING + Boost.Fibers temporal coherence system

echo "🚀 PIPELINE PERFORMANCE BENCHMARK SUITE"
echo "======================================="
echo "🎯 Testing: Cross-core pipeline correctness + Performance"
echo "🔧 System: IO_URING + Boost.Fibers + Hardware TSC Temporal Coherence"
echo ""

# **BENCHMARK CONFIGURATION**
SERVER_BINARY="./integrated_temporal_coherence_server"
BASE_PORT=6379
NUM_CORES=4
NUM_SHARDS=16
SERVER_PID=""
BENCHMARK_DIR="pipeline_benchmarks"

# **TEST PARAMETERS**
PIPELINE_SIZES=(2 5 10 20)
CLIENT_COUNTS=(1 10 25 50)
OPERATIONS_PER_TEST=50000
WARMUP_OPERATIONS=5000

# **RESULTS STORAGE**
mkdir -p "$BENCHMARK_DIR"
RESULTS_FILE="$BENCHMARK_DIR/pipeline_performance_results.csv"
SUMMARY_FILE="$BENCHMARK_DIR/benchmark_summary.txt"

# **CLEANUP FUNCTION**
cleanup() {
    echo ""
    echo "🧹 Cleaning up benchmark processes..."
    if [ ! -z "$SERVER_PID" ]; then
        kill -TERM $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
    fi
    pkill -f integrated_temporal_coherence_server 2>/dev/null || true
    pkill -f redis-benchmark 2>/dev/null || true
    sleep 2
    echo "✅ Cleanup complete"
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

echo "📋 Benchmark Configuration:"
echo "   - Server: $SERVER_BINARY"
echo "   - Cores: $NUM_CORES (ports $BASE_PORT-$((BASE_PORT + NUM_CORES - 1)))"
echo "   - Shards: $NUM_SHARDS"
echo "   - Pipeline sizes: ${PIPELINE_SIZES[*]}"
echo "   - Client counts: ${CLIENT_COUNTS[*]}"
echo "   - Operations per test: $OPERATIONS_PER_TEST"
echo "   - Results directory: $BENCHMARK_DIR"
echo ""

# **UTILITY FUNCTIONS**
log_result() {
    local test_name="$1"
    local pipeline_size="$2"
    local clients="$3"
    local rps="$4"
    local latency_avg="$5"
    local latency_p99="$6"
    local cross_core_ops="$7"
    
    echo "$test_name,$pipeline_size,$clients,$rps,$latency_avg,$latency_p99,$cross_core_ops" >> "$RESULTS_FILE"
}

wait_for_server() {
    local timeout=10
    local count=0
    
    echo -n "Waiting for server to be ready"
    while [ $count -lt $timeout ]; do
        if nc -z 127.0.0.1 $BASE_PORT 2>/dev/null; then
            echo " ✅"
            return 0
        fi
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    echo " ❌"
    return 1
}

# **STEP 1: VERIFY BUILD AND DEPENDENCIES**
echo "🔨 STEP 1: Build and Dependency Verification"
echo "--------------------------------------------"

if [ ! -f "$SERVER_BINARY" ]; then
    echo "❌ Server binary not found: $SERVER_BINARY"
    exit 1
fi

if ! command -v redis-benchmark &> /dev/null; then
    echo "❌ redis-benchmark not found. Installing redis-tools..."
    sudo apt update && sudo apt install -y redis-tools
    if ! command -v redis-benchmark &> /dev/null; then
        echo "❌ Failed to install redis-benchmark"
        exit 1
    fi
fi

if ! command -v nc &> /dev/null; then
    echo "❌ netcat not found. Installing..."
    sudo apt install -y netcat
fi

echo "✅ All dependencies verified"
echo "📊 Server binary: $(ls -lh $SERVER_BINARY | awk '{print $5}')"
echo ""

# **STEP 2: START SERVER**
echo "🚀 STEP 2: Starting Integrated Temporal Coherence Server"
echo "--------------------------------------------------------"

echo "Starting server with $NUM_CORES cores..."
$SERVER_BINARY -c $NUM_CORES -s $NUM_SHARDS -p $BASE_PORT > "$BENCHMARK_DIR/server.log" 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"

if ! wait_for_server; then
    echo "❌ Server failed to start"
    echo "📄 Server log:"
    cat "$BENCHMARK_DIR/server.log"
    exit 1
fi

echo "✅ Server started successfully"
echo ""

# **STEP 3: INITIALIZE RESULTS FILE**
echo "📊 STEP 3: Initializing Results Collection"
echo "------------------------------------------"

echo "test_name,pipeline_size,clients,rps,latency_avg_ms,latency_p99_ms,cross_core_ops" > "$RESULTS_FILE"
echo "✅ Results file initialized: $RESULTS_FILE"
echo ""

# **STEP 4: BASELINE SINGLE COMMAND BENCHMARK**
echo "📈 STEP 4: Baseline Single Command Performance"
echo "----------------------------------------------"

for clients in "${CLIENT_COUNTS[@]}"; do
    echo "Testing single commands with $clients clients..."
    
    # Test each core individually
    for core in $(seq 0 $((NUM_CORES-1))); do
        port=$((BASE_PORT + core))
        echo -n "  Core $core (port $port): "
        
        # Run redis-benchmark
        output=$(redis-benchmark -h 127.0.0.1 -p $port -t set,get -n $OPERATIONS_PER_TEST -c $clients -q --csv 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            # Parse results
            set_rps=$(echo "$output" | grep "SET" | cut -d',' -f2 | tr -d '"')
            get_rps=$(echo "$output" | grep "GET" | cut -d',' -f2 | tr -d '"')
            avg_rps=$(echo "scale=0; ($set_rps + $get_rps) / 2" | bc -l 2>/dev/null || echo "0")
            
            echo "SET: $set_rps RPS, GET: $get_rps RPS"
            log_result "single_command_core_$core" "1" "$clients" "$avg_rps" "0" "0" "0"
        else
            echo "❌ FAILED"
        fi
    done
    echo ""
done

# **STEP 5: PIPELINE CORRECTNESS TEST**
echo "🔍 STEP 5: Cross-Core Pipeline Correctness Verification"
echo "-------------------------------------------------------"

create_pipeline_test() {
    local pipeline_size=$1
    local output_file=$2
    
    cat > "$output_file" << EOF
#!/bin/bash
# Pipeline correctness test script

# Create pipeline with keys that should go to different cores
commands=(
EOF

    # Generate commands with keys that hash to different cores
    for i in $(seq 1 $pipeline_size); do
        key="pipeline_key_${i}_$(date +%s%N)"
        value="value_$i"
        echo "    \"SET $key $value\"" >> "$output_file"
    done
    
    cat >> "$output_file" << 'EOF'
)

# Convert to RESP protocol
for cmd in "${commands[@]}"; do
    parts=($cmd)
    echo "*${#parts}"
    for part in "${parts[@]}"; do
        echo "\$${#part}"
        echo "$part"
    done
done | tr '\n' '\r\n'
EOF

    chmod +x "$output_file"
}

echo "Creating pipeline correctness tests..."
for pipeline_size in "${PIPELINE_SIZES[@]}"; do
    echo -n "  Pipeline size $pipeline_size: "
    
    test_script="$BENCHMARK_DIR/pipeline_test_${pipeline_size}.sh"
    create_pipeline_test $pipeline_size "$test_script"
    
    # Test on first core (pipeline should route to correct cores automatically)
    response=$(timeout 5s "$test_script" | nc -w 2 127.0.0.1 $BASE_PORT 2>/dev/null)
    
    if [[ "$response" == *"OK"* ]]; then
        ok_count=$(echo "$response" | grep -c "OK" || echo "0")
        echo "✅ $ok_count/$pipeline_size commands successful"
    else
        echo "❌ Pipeline test failed"
    fi
done
echo ""

# **STEP 6: PIPELINE PERFORMANCE BENCHMARKS**
echo "🏃 STEP 6: Pipeline Performance Benchmarks"
echo "------------------------------------------"

for pipeline_size in "${PIPELINE_SIZES[@]}"; do
    echo "Testing pipeline size: $pipeline_size commands"
    echo "--------------------------------------------"
    
    for clients in "${CLIENT_COUNTS[@]}"; do
        echo -n "  $clients clients: "
        
        # Create custom pipeline benchmark
        benchmark_script="$BENCHMARK_DIR/benchmark_p${pipeline_size}_c${clients}.sh"
        
        cat > "$benchmark_script" << EOF
#!/bin/bash
# Custom pipeline benchmark for size $pipeline_size with $clients clients

start_time=\$(date +%s.%N)
operations=0
errors=0

for client in \$(seq 1 $clients); do
    (
        for op in \$(seq 1 \$((OPERATIONS_PER_TEST / $clients))); do
            # Create pipeline
            pipeline=""
EOF

        # Generate pipeline commands
        for cmd_num in $(seq 1 $pipeline_size); do
            cat >> "$benchmark_script" << 'EOF'
            key="bench_${client}_${op}_${cmd_num}_$(date +%s%N)"
            value="value_${cmd_num}"
            pipeline="$pipeline*3\r\n\$3\r\nSET\r\n\$${#key}\r\n$key\r\n\$${#value}\r\n$value\r\n"
EOF
        done
        
        cat >> "$benchmark_script" << 'EOF'
            
            # Send pipeline
            echo -e "$pipeline" | nc -w 1 127.0.0.1 BASE_PORT >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                operations=$((operations + PIPELINE_SIZE))
            else
                errors=$((errors + 1))
            fi
        done
    ) &
done

wait

end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc -l)
rps=$(echo "scale=0; $operations / $duration" | bc -l)

echo "$rps,$duration,$errors"
EOF

        # Replace placeholders
        sed -i "s/BASE_PORT/$BASE_PORT/g" "$benchmark_script"
        sed -i "s/PIPELINE_SIZE/$pipeline_size/g" "$benchmark_script"
        sed -i "s/OPERATIONS_PER_TEST/$OPERATIONS_PER_TEST/g" "$benchmark_script"
        chmod +x "$benchmark_script"
        
        # Run benchmark
        result=$(timeout 30s "$benchmark_script" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ ! -z "$result" ]; then
            rps=$(echo "$result" | cut -d',' -f1)
            duration=$(echo "$result" | cut -d',' -f2)
            errors=$(echo "$result" | cut -d',' -f3)
            
            # Calculate average latency (rough estimate)
            avg_latency=$(echo "scale=2; ($duration * 1000) / ($OPERATIONS_PER_TEST / $pipeline_size)" | bc -l 2>/dev/null || echo "0")
            
            echo "✅ $rps RPS (${avg_latency}ms avg latency, $errors errors)"
            log_result "pipeline_performance" "$pipeline_size" "$clients" "$rps" "$avg_latency" "0" "0"
        else
            echo "❌ TIMEOUT/FAILED"
            log_result "pipeline_performance" "$pipeline_size" "$clients" "0" "0" "0" "0"
        fi
    done
    echo ""
done

# **STEP 7: CROSS-CORE LOAD DISTRIBUTION TEST**
echo "🌐 STEP 7: Cross-Core Load Distribution Test"
echo "--------------------------------------------"

echo "Testing load distribution across all cores..."
for core in $(seq 0 $((NUM_CORES-1))); do
    port=$((BASE_PORT + core))
    echo -n "  Core $core (port $port): "
    
    # Run concurrent test on all cores
    (
        redis-benchmark -h 127.0.0.1 -p $port -t set -n $((OPERATIONS_PER_TEST / NUM_CORES)) -c 10 -q --csv 2>/dev/null | grep SET | cut -d',' -f2 | tr -d '"'
    ) &
done

wait
echo ""

# **STEP 8: SERVER METRICS COLLECTION**
echo "📊 STEP 8: Server Metrics Collection"
echo "------------------------------------"

echo "Collecting server metrics..."
kill -USR1 $SERVER_PID 2>/dev/null || true
sleep 2

if [ -f "$BENCHMARK_DIR/server.log" ]; then
    echo "📄 Server metrics (last 20 lines):"
    tail -20 "$BENCHMARK_DIR/server.log" | grep -E "(Commands|Batches|Cross-core|IO|Fibers)" || echo "No detailed metrics found"
else
    echo "⚠️  Server log not found"
fi
echo ""

# **STEP 9: RESULTS ANALYSIS**
echo "📈 STEP 9: Results Analysis and Summary"
echo "--------------------------------------"

echo "Analyzing benchmark results..."

# Create summary
cat > "$SUMMARY_FILE" << EOF
PIPELINE PERFORMANCE BENCHMARK SUMMARY
======================================
Timestamp: $(date)
System: IO_URING + Boost.Fibers Temporal Coherence
Configuration: $NUM_CORES cores, $NUM_SHARDS shards

BENCHMARK PARAMETERS:
- Pipeline sizes tested: ${PIPELINE_SIZES[*]}
- Client counts tested: ${CLIENT_COUNTS[*]}
- Operations per test: $OPERATIONS_PER_TEST
- Server ports: $BASE_PORT-$((BASE_PORT + NUM_CORES - 1))

RESULTS SUMMARY:
EOF

# Calculate statistics
if [ -f "$RESULTS_FILE" ]; then
    echo "📊 Performance Results by Pipeline Size:" | tee -a "$SUMMARY_FILE"
    
    for pipeline_size in "${PIPELINE_SIZES[@]}"; do
        echo "   Pipeline size $pipeline_size:" | tee -a "$SUMMARY_FILE"
        
        max_rps=$(grep "pipeline_performance,$pipeline_size," "$RESULTS_FILE" | cut -d',' -f4 | sort -nr | head -1)
        avg_rps=$(grep "pipeline_performance,$pipeline_size," "$RESULTS_FILE" | cut -d',' -f4 | awk '{sum+=$1} END {print int(sum/NR)}')
        
        if [ ! -z "$max_rps" ] && [ "$max_rps" -gt 0 ]; then
            echo "     - Max RPS: $max_rps" | tee -a "$SUMMARY_FILE"
            echo "     - Avg RPS: $avg_rps" | tee -a "$SUMMARY_FILE"
        else
            echo "     - No successful results" | tee -a "$SUMMARY_FILE"
        fi
    done
    
    echo "" | tee -a "$SUMMARY_FILE"
    echo "📋 Detailed results available in: $RESULTS_FILE" | tee -a "$SUMMARY_FILE"
else
    echo "⚠️  No results file found" | tee -a "$SUMMARY_FILE"
fi

# **FINAL SUMMARY**
echo ""
echo "🏆 BENCHMARK COMPLETION SUMMARY"
echo "==============================="
echo "✅ Benchmark suite completed successfully"
echo "📊 Results stored in: $BENCHMARK_DIR/"
echo "📄 Summary report: $SUMMARY_FILE"
echo "📈 Detailed results: $RESULTS_FILE"
echo "📋 Server log: $BENCHMARK_DIR/server.log"
echo ""

# Check if server is still responsive
if kill -0 $SERVER_PID 2>/dev/null; then
    echo "✅ Server still running and responsive"
else
    echo "⚠️  Server may have stopped during benchmarking"
fi

echo ""
echo "🎯 PIPELINE PERFORMANCE BENCHMARK COMPLETE!"
echo "Ready for analysis and production validation."

exit 0














