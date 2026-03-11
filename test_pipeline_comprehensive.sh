#!/bin/bash

echo "=== 🚀 PHASE 7 STEP 1: COMPREHENSIVE PIPELINE TEST 🚀 ==="
echo "📊 Objective: Validate 3x improvement over Phase 6 Step 3 (800K → 2.4M+ RPS)"
echo "🔧 Method: Test simplified pipeline + DragonflyDB architecture"
echo ""

# Function to safely kill processes
cleanup() {
    echo "🧹 Cleaning up processes..."
    pkill -f meteor_phase7 || true
    pkill -f meteor_simplified || true
    sleep 3
    pkill -9 -f meteor || true
}

# Cleanup any existing processes
cleanup

echo "=== 🔨 BUILDING SIMPLIFIED PIPELINE VERSION ==="
echo "Building with optimizations..."

if g++ -std=c++17 -O3 -march=native -DHAS_LINUX_EPOLL=1 -DHAS_IO_URING=1 -I. \
    sharded_server_phase7_step1_simplified_pipeline.cpp \
    -o meteor_simplified \
    $(pkg-config --libs liburing 2>/dev/null || echo "") -lpthread; then
    echo "✅ Simplified pipeline build successful!"
    ls -la meteor_simplified
else
    echo "❌ Build failed, trying without io_uring..."
    if g++ -std=c++17 -O3 -march=native -DHAS_LINUX_EPOLL=1 -I. \
        sharded_server_phase7_step1_simplified_pipeline.cpp \
        -o meteor_simplified -lpthread; then
        echo "✅ Simplified pipeline build successful (epoll mode)!"
        ls -la meteor_simplified
    else
        echo "❌ Build completely failed"
        exit 1
    fi
fi

echo ""
echo "=== 🚀 TESTING PIPELINE PERFORMANCE ==="

# Start server in background
echo "Starting simplified pipeline server (4 cores)..."
timeout 300s ./meteor_simplified -p 6379 -c 4 > simplified_server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to initialize
sleep 8

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    echo "Server log:"
    cat simplified_server.log 2>/dev/null | tail -20
    exit 1
fi

echo "✅ Server is running"

# Show server initialization
echo ""
echo "=== 🔍 SERVER INITIALIZATION STATUS ==="
if [ -f simplified_server.log ]; then
    echo "Initialization messages:"
    grep -E "(initialized|started|listening)" simplified_server.log | head -10
    echo ""
fi

# Basic connectivity test
echo "=== 🔌 CONNECTIVITY TEST ==="
echo "Testing basic PING..."
PING_RESULT=$(echo -e "PING\r\n" | timeout 5s nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r\n' || echo "FAILED")
echo "PING response: '$PING_RESULT'"

if [ "$PING_RESULT" = "FAILED" ] || [ -z "$PING_RESULT" ]; then
    echo "❌ Basic connectivity failed"
    echo "Checking server status..."
    ps aux | grep meteor_simplified | grep -v grep || echo "Server not running"
    echo "Recent server log:"
    tail -10 simplified_server.log 2>/dev/null
    cleanup
    exit 1
fi

echo "✅ Basic connectivity working"

# Performance tests
echo ""
echo "=== 📊 PERFORMANCE BENCHMARK SUITE ==="

# Test function
run_benchmark() {
    local test_name="$1"
    local pipeline_depth="$2"
    local connections="$3"
    local requests="$4"
    local output_file="$5"
    
    echo ""
    echo "🔸 $test_name (P$pipeline_depth, C$connections, N$requests):"
    
    timeout 90s redis-benchmark \
        -h 127.0.0.1 -p 6379 \
        -t set,get \
        -n $requests \
        -c $connections \
        -P $pipeline_depth \
        -q > "$output_file" 2>&1
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -s "$output_file" ]; then
        echo "✅ $test_name completed successfully"
        cat "$output_file"
        
        # Extract SET RPS
        local set_rps=$(grep "SET:" "$output_file" | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        local get_rps=$(grep "GET:" "$output_file" | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        
        if [ ! -z "$set_rps" ]; then
            echo "🎯 SET Performance: $set_rps RPS"
        fi
        if [ ! -z "$get_rps" ]; then
            echo "🎯 GET Performance: $get_rps RPS"
        fi
        
        # Return the SET RPS for comparison
        echo "$set_rps"
    else
        echo "❌ $test_name failed or timed out"
        if [ -s "$output_file" ]; then
            echo "Partial output:"
            head -5 "$output_file"
        fi
        echo "0"
    fi
}

# Baseline test (P1)
BASELINE_RPS=$(run_benchmark "Baseline P1" 1 20 50000 "baseline.txt")

# Pipeline tests
P10_RPS=$(run_benchmark "Pipeline P10" 10 30 100000 "pipeline_p10.txt")
P30_RPS=$(run_benchmark "Pipeline P30" 30 50 150000 "pipeline_p30.txt")
P100_RPS=$(run_benchmark "Pipeline P100" 100 100 200000 "pipeline_p100.txt")

echo ""
echo "=== 📈 PERFORMANCE ANALYSIS ==="

# Find highest RPS
HIGHEST_RPS=0
BEST_TEST=""

check_rps() {
    local rps="$1"
    local test="$2"
    
    if [ ! -z "$rps" ] && [ "$rps" != "0" ]; then
        local rps_int=$(echo "$rps" | cut -d. -f1)
        if [ "$rps_int" -gt "$HIGHEST_RPS" ]; then
            HIGHEST_RPS=$rps_int
            BEST_TEST="$test"
        fi
    fi
}

check_rps "$BASELINE_RPS" "Baseline P1"
check_rps "$P10_RPS" "Pipeline P10"
check_rps "$P30_RPS" "Pipeline P30"
check_rps "$P100_RPS" "Pipeline P100"

echo "Performance Summary:"
echo "==================="
echo "Baseline P1:     ${BASELINE_RPS:-0} RPS"
echo "Pipeline P10:    ${P10_RPS:-0} RPS"
echo "Pipeline P30:    ${P30_RPS:-0} RPS"
echo "Pipeline P100:   ${P100_RPS:-0} RPS"
echo ""
echo "Best Result:     $HIGHEST_RPS RPS ($BEST_TEST)"

# Calculate improvements
if [ ! -z "$BASELINE_RPS" ] && [ "$BASELINE_RPS" != "0" ]; then
    echo ""
    echo "Pipeline Improvements:"
    echo "====================="
    
    if [ ! -z "$P10_RPS" ] && [ "$P10_RPS" != "0" ]; then
        P10_IMPROVEMENT=$(echo "scale=1; $P10_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
        echo "P10 vs Baseline: ${P10_IMPROVEMENT}x"
    fi
    
    if [ ! -z "$P30_RPS" ] && [ "$P30_RPS" != "0" ]; then
        P30_IMPROVEMENT=$(echo "scale=1; $P30_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
        echo "P30 vs Baseline: ${P30_IMPROVEMENT}x"
    fi
    
    if [ ! -z "$P100_RPS" ] && [ "$P100_RPS" != "0" ]; then
        P100_IMPROVEMENT=$(echo "scale=1; $P100_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
        echo "P100 vs Baseline: ${P100_IMPROVEMENT}x"
    fi
fi

echo ""
echo "=== 🎯 3x IMPROVEMENT VALIDATION ==="
echo "Target: Phase 6 Step 3 (800K RPS) → Phase 7 Step 1 (2.4M+ RPS)"
echo ""

# Validate against targets
if [ "$HIGHEST_RPS" -gt "2400000" ]; then
    IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
    echo "🎉🎉🎉 SUCCESS: 3x TARGET ACHIEVED! 🎉🎉🎉"
    echo "🏆 Peak Performance: $HIGHEST_RPS RPS"
    echo "📈 Improvement: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
    echo "✅ Pipeline fix is working and beating benchmarks!"
    
elif [ "$HIGHEST_RPS" -gt "1600000" ]; then
    IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
    echo "🚀🚀 EXCELLENT: 2x+ IMPROVEMENT! 🚀🚀"
    echo "📊 Peak Performance: $HIGHEST_RPS RPS"
    echo "📈 Improvement: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
    echo "✅ Pipeline fix is working well, close to 3x target!"
    
elif [ "$HIGHEST_RPS" -gt "800000" ]; then
    IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
    echo "📈 GOOD: Beating Phase 6 Step 3 baseline!"
    echo "📊 Peak Performance: $HIGHEST_RPS RPS"
    echo "📈 Improvement: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
    echo "✅ Pipeline fix shows clear improvement"
    
else
    echo "📊 NEEDS WORK: Performance below Phase 6 Step 3"
    echo "🔍 Current Peak: $HIGHEST_RPS RPS"
    echo "❌ Pipeline fix needs further optimization"
fi

# Server activity analysis
echo ""
echo "=== 🔍 SERVER ACTIVITY ANALYSIS ==="
if [ -f simplified_server.log ]; then
    echo "Connections accepted: $(grep -c "accepted connection" simplified_server.log 2>/dev/null || echo '0')"
    echo "Commands processed: $(grep -c "processing:" simplified_server.log 2>/dev/null || echo '0')"
    echo "Responses sent: $(grep -c "sending.*responses" simplified_server.log 2>/dev/null || echo '0')"
    
    echo ""
    echo "Sample command processing:"
    grep "processing:" simplified_server.log | head -3 2>/dev/null || echo "No command processing logs"
    
    echo ""
    echo "Sample response batching:"
    grep "sending.*responses" simplified_server.log | head -3 2>/dev/null || echo "No response batching logs"
fi

# Cleanup
cleanup

echo ""
echo "=== 🏁 COMPREHENSIVE PIPELINE TEST COMPLETED ==="
echo "🎯 Objective: Validate pipeline fix and 3x improvement"
echo "📊 Result: Peak performance $HIGHEST_RPS RPS ($BEST_TEST)"

# Exit with appropriate code
if [ "$HIGHEST_RPS" -gt "800000" ]; then
    echo "✅ PIPELINE FIX IS WORKING AND BEATING BENCHMARKS!"
    exit 0
else
    echo "❌ Pipeline fix needs more work"
    exit 1
fi