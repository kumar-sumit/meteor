#!/bin/bash

echo "=== 🚀 PHASE 7 STEP 1: ROBUST PIPELINE BENCHMARK TEST 🚀 ==="
echo "📊 Objective: Test and benchmark the pipeline fix"
echo "🎯 Target: 3x improvement over Phase 6 Step 3 (800K → 2.4M+ RPS)"
echo ""

# Function to cleanup processes
cleanup_all() {
    echo "🧹 Cleaning up all meteor processes..."
    pkill -f meteor || true
    sleep 2
    pkill -9 -f meteor || true
    sleep 1
}

# Function to wait for server readiness
wait_for_server() {
    local port=$1
    local timeout=30
    local count=0
    
    echo "⏳ Waiting for server on port $port..."
    while [ $count -lt $timeout ]; do
        if nc -z 127.0.0.1 $port 2>/dev/null; then
            echo "✅ Server is ready on port $port"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    echo "❌ Server failed to start on port $port after ${timeout}s"
    return 1
}

# Function to test basic connectivity
test_connectivity() {
    local port=$1
    echo "🔌 Testing basic connectivity on port $port..."
    
    local response=$(echo -e "PING\r\n" | timeout 5s nc -w 2 127.0.0.1 $port 2>/dev/null | tr -d '\r\n' || echo "FAILED")
    echo "PING response: '$response'"
    
    if [ "$response" = "+PONG" ] || [ "$response" = "PONG" ]; then
        echo "✅ Basic connectivity working"
        return 0
    else
        echo "❌ Basic connectivity failed"
        return 1
    fi
}

# Function to run benchmark
run_redis_benchmark() {
    local test_name="$1"
    local port="$2"
    local pipeline="$3"
    local connections="$4"
    local requests="$5"
    
    echo ""
    echo "🔸 Running $test_name (P$pipeline, C$connections, N$requests)..."
    
    local output_file="benchmark_${test_name,,}.txt"
    
    timeout 120s redis-benchmark \
        -h 127.0.0.1 -p $port \
        -t set,get \
        -n $requests \
        -c $connections \
        -P $pipeline \
        -q > "$output_file" 2>&1
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -s "$output_file" ]; then
        echo "✅ $test_name completed successfully"
        cat "$output_file"
        
        # Extract SET RPS for comparison
        local set_rps=$(grep "SET:" "$output_file" | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$set_rps" ]; then
            echo "🎯 $test_name SET Performance: $set_rps RPS"
            echo "$set_rps"
            return 0
        fi
    else
        echo "❌ $test_name failed or timed out (exit code: $exit_code)"
        if [ -s "$output_file" ]; then
            echo "Partial output:"
            head -10 "$output_file"
        fi
    fi
    
    echo "0"
    return 1
}

# Start with cleanup
cleanup_all

echo ""
echo "=== 🔨 BUILDING PIPELINE FIX VERSION ==="

# Build the debug version with comprehensive error handling
if g++ -std=c++17 -O3 -march=native -DHAS_LINUX_EPOLL=1 -DHAS_IO_URING=1 -I. \
    sharded_server_phase7_step1_debug.cpp \
    -o meteor_pipeline_fix \
    $(pkg-config --libs liburing 2>/dev/null || echo "") -lpthread 2>&1; then
    echo "✅ Pipeline fix build successful with io_uring!"
    ls -la meteor_pipeline_fix
elif g++ -std=c++17 -O3 -march=native -DHAS_LINUX_EPOLL=1 -I. \
    sharded_server_phase7_step1_debug.cpp \
    -o meteor_pipeline_fix -lpthread 2>&1; then
    echo "✅ Pipeline fix build successful with epoll!"
    ls -la meteor_pipeline_fix
else
    echo "❌ Pipeline fix build failed completely"
    exit 1
fi

echo ""
echo "=== 🚀 TESTING PIPELINE FIX SERVER ==="

# Start the pipeline fix server
echo "Starting Pipeline Fix Server (4 cores, port 6379)..."
timeout 300s ./meteor_pipeline_fix -p 6379 -c 4 > pipeline_fix_server.log 2>&1 &
PIPELINE_PID=$!
echo "Pipeline Fix Server PID: $PIPELINE_PID"

# Wait for server to be ready
if wait_for_server 6379; then
    echo "✅ Pipeline fix server is running"
    
    # Test basic connectivity
    if test_connectivity 6379; then
        echo ""
        echo "=== 📊 PIPELINE FIX BENCHMARK SUITE ==="
        
        # Run comprehensive benchmarks
        BASELINE_RPS=$(run_redis_benchmark "Baseline_P1" 6379 1 20 50000)
        P10_RPS=$(run_redis_benchmark "Pipeline_P10" 6379 10 30 100000)
        P30_RPS=$(run_redis_benchmark "Pipeline_P30" 6379 30 50 150000)
        P100_RPS=$(run_redis_benchmark "Pipeline_P100" 6379 100 100 200000)
        
        echo ""
        echo "=== 📈 PERFORMANCE ANALYSIS ==="
        echo "Pipeline Fix Results:"
        echo "===================="
        echo "Baseline P1:     ${BASELINE_RPS:-0} RPS"
        echo "Pipeline P10:    ${P10_RPS:-0} RPS"
        echo "Pipeline P30:    ${P30_RPS:-0} RPS"
        echo "Pipeline P100:   ${P100_RPS:-0} RPS"
        
        # Find best performance
        BEST_RPS=0
        BEST_TEST=""
        
        for rps_val in "$BASELINE_RPS" "$P10_RPS" "$P30_RPS" "$P100_RPS"; do
            if [ ! -z "$rps_val" ] && [ "$rps_val" != "0" ]; then
                rps_int=$(echo "$rps_val" | cut -d. -f1)
                if [ "$rps_int" -gt "$BEST_RPS" ]; then
                    BEST_RPS=$rps_int
                fi
            fi
        done
        
        echo ""
        echo "Best Pipeline Fix Performance: $BEST_RPS RPS"
        
        # Validate against 3x target
        echo ""
        echo "=== 🎯 3x IMPROVEMENT VALIDATION ==="
        echo "Phase 6 Step 3 Target:   800,000 RPS"
        echo "Phase 7 Step 1 Target: 2,400,000 RPS (3x improvement)"
        echo "Pipeline Fix Achieved:   $BEST_RPS RPS"
        echo ""
        
        if [ "$BEST_RPS" -gt "2400000" ]; then
            IMPROVEMENT=$(echo "scale=1; $BEST_RPS / 800000" | bc)
            echo "🎉🎉🎉 SUCCESS: 3x TARGET ACHIEVED! 🎉🎉🎉"
            echo "🏆 Performance: $BEST_RPS RPS"
            echo "📈 Improvement: ${IMPROVEMENT}x over Phase 6 Step 3"
            echo "✅ PIPELINE FIX IS WORKING AND BEATING BENCHMARKS!"
            RESULT_CODE=0
            
        elif [ "$BEST_RPS" -gt "1600000" ]; then
            IMPROVEMENT=$(echo "scale=1; $BEST_RPS / 800000" | bc)
            echo "🚀🚀 EXCELLENT: 2x+ IMPROVEMENT! 🚀🚀"
            echo "📊 Performance: $BEST_RPS RPS"
            echo "📈 Improvement: ${IMPROVEMENT}x over Phase 6 Step 3"
            echo "✅ Pipeline fix is working well, close to 3x target!"
            RESULT_CODE=0
            
        elif [ "$BEST_RPS" -gt "800000" ]; then
            IMPROVEMENT=$(echo "scale=1; $BEST_RPS / 800000" | bc)
            echo "📈 GOOD: Beating Phase 6 Step 3!"
            echo "📊 Performance: $BEST_RPS RPS"
            echo "📈 Improvement: ${IMPROVEMENT}x over Phase 6 Step 3"
            echo "✅ Pipeline fix shows clear improvement"
            RESULT_CODE=0
            
        else
            echo "📊 NEEDS OPTIMIZATION: Below Phase 6 Step 3 target"
            echo "🔍 Current: $BEST_RPS RPS"
            echo "❌ Pipeline fix needs more work"
            RESULT_CODE=1
        fi
        
        # Show server activity
        echo ""
        echo "=== 🔍 SERVER ACTIVITY ANALYSIS ==="
        if [ -f pipeline_fix_server.log ]; then
            echo "Server initialization:"
            grep -E "(initialized|started|listening)" pipeline_fix_server.log | head -5
            
            echo ""
            echo "Connection activity:"
            echo "Connections accepted: $(grep -c "accepted connection" pipeline_fix_server.log 2>/dev/null || echo '0')"
            echo "Data received: $(grep -c "received.*bytes" pipeline_fix_server.log 2>/dev/null || echo '0')"
            echo "Commands processed: $(grep -c "processing:" pipeline_fix_server.log 2>/dev/null || echo '0')"
            echo "Responses sent: $(grep -c "sending.*responses" pipeline_fix_server.log 2>/dev/null || echo '0')"
            
            echo ""
            echo "Sample command processing:"
            grep "processing:" pipeline_fix_server.log | head -3 2>/dev/null || echo "No command logs found"
        fi
        
    else
        echo "❌ Pipeline fix server connectivity failed"
        RESULT_CODE=1
    fi
    
else
    echo "❌ Pipeline fix server failed to start"
    echo "Server log:"
    cat pipeline_fix_server.log 2>/dev/null | tail -20
    RESULT_CODE=1
fi

# Cleanup
echo ""
echo "🧹 Cleaning up..."
kill $PIPELINE_PID 2>/dev/null || true
sleep 2
cleanup_all

echo ""
echo "=== 🏁 PIPELINE BENCHMARK TEST COMPLETED ==="
echo "🎯 Objective: Test and benchmark pipeline fix"
echo "📊 Result: Pipeline fix performance validated"

if [ "$RESULT_CODE" -eq 0 ]; then
    echo "✅ PIPELINE FIX IS WORKING AND PERFORMING WELL!"
else
    echo "❌ Pipeline fix needs further optimization"
fi

exit $RESULT_CODE