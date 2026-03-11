#!/bin/bash

# **PHASE 7 STEP 1: Advanced io_uring Performance Test**
# Tests multiple io_uring optimization levels

echo "=== 🚀 ADVANCED io_uring PERFORMANCE TEST (Phase 7 Step 1) 🚀 ==="
echo "🎯 Testing progressive io_uring optimizations"
echo ""

# Test configurations
BASIC_CONFIG="METEOR_USE_IO_URING=1"
ADVANCED_CONFIG="METEOR_USE_IO_URING=1 METEOR_USE_SQPOLL=1"
ULTIMATE_CONFIG="METEOR_USE_IO_URING=1 METEOR_USE_SQPOLL=1 METEOR_USE_MULTISHOT=1"

# Performance test function
run_performance_test() {
    local config_name="$1"
    local config_env="$2"
    local port="$3"
    
    echo "=== TESTING $config_name CONFIGURATION ==="
    echo "Environment: $config_env"
    
    # Start server
    echo "Starting server..."
    eval "$config_env ./meteor_incremental_iouring -h 127.0.0.1 -p $port -c 4" &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 2
    
    # Test connectivity
    echo "Testing connectivity..."
    if timeout 5 redis-cli -p $port ping > /dev/null 2>&1; then
        echo "✅ Server responding"
    else
        echo "❌ Server not responding"
        kill $SERVER_PID 2>/dev/null
        return 1
    fi
    
    # Run performance benchmark
    echo "Running performance benchmark..."
    redis-benchmark -p $port -c 50 -n 10000 -t set,get -q --csv > "results_${config_name,,}.csv" 2>/dev/null
    
    # Get specific metrics
    echo "Performance Results:"
    SET_RPS=$(redis-benchmark -p $port -c 50 -n 10000 -t set -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    GET_RPS=$(redis-benchmark -p $port -c 50 -n 10000 -t get -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    
    echo "  SET: ${SET_RPS:-0} RPS"
    echo "  GET: ${GET_RPS:-0} RPS"
    
    # Test pipelining
    echo "Testing pipeline performance..."
    PIPELINE_RPS=$(redis-benchmark -p $port -c 50 -n 10000 -P 10 -t set,get -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    echo "  Pipeline (10): ${PIPELINE_RPS:-0} RPS"
    
    # Stop server
    kill $SERVER_PID 2>/dev/null
    wait $SERVER_PID 2>/dev/null
    
    # Store results
    echo "$config_name,${SET_RPS:-0},${GET_RPS:-0},${PIPELINE_RPS:-0}" >> performance_comparison.csv
    
    sleep 1
    echo ""
}

# Initialize results file
echo "Configuration,SET_RPS,GET_RPS,PIPELINE_RPS" > performance_comparison.csv

# Test baseline epoll
echo "=== BASELINE EPOLL TEST ==="
./meteor_incremental_iouring -h 127.0.0.1 -p 6380 -c 4 &
BASELINE_PID=$!
sleep 2

if timeout 5 redis-cli -p 6380 ping > /dev/null 2>&1; then
    echo "✅ Baseline epoll responding"
    BASELINE_SET=$(redis-benchmark -p 6380 -c 50 -n 10000 -t set -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    BASELINE_GET=$(redis-benchmark -p 6380 -c 50 -n 10000 -t get -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    BASELINE_PIPELINE=$(redis-benchmark -p 6380 -c 50 -n 10000 -P 10 -t set,get -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    
    echo "Baseline Results:"
    echo "  SET: ${BASELINE_SET:-0} RPS"
    echo "  GET: ${BASELINE_GET:-0} RPS"
    echo "  Pipeline: ${BASELINE_PIPELINE:-0} RPS"
    
    echo "EPOLL_BASELINE,${BASELINE_SET:-0},${BASELINE_GET:-0},${BASELINE_PIPELINE:-0}" >> performance_comparison.csv
else
    echo "❌ Baseline epoll not responding"
fi

kill $BASELINE_PID 2>/dev/null
wait $BASELINE_PID 2>/dev/null
sleep 1

# Test different io_uring configurations
run_performance_test "BASIC_IOURING" "$BASIC_CONFIG" "6381"
run_performance_test "SQPOLL_IOURING" "$ADVANCED_CONFIG" "6382"
run_performance_test "ULTIMATE_IOURING" "$ULTIMATE_CONFIG" "6383"

# Generate summary report
echo "=== 📊 PERFORMANCE COMPARISON SUMMARY 📊 ==="
echo ""
echo "Configuration        | SET RPS    | GET RPS    | Pipeline RPS | Improvement"
echo "--------------------+-----------+-----------+-------------+------------"

# Read and display results
while IFS=',' read -r config set_rps get_rps pipeline_rps; do
    if [ "$config" != "Configuration" ]; then
        # Calculate improvement over baseline
        if [ "$config" = "EPOLL_BASELINE" ]; then
            improvement="Baseline"
            baseline_total=$(echo "$set_rps + $get_rps" | bc 2>/dev/null || echo "0")
        else
            if [ -n "$baseline_total" ] && [ "$baseline_total" != "0" ]; then
                current_total=$(echo "$set_rps + $get_rps" | bc 2>/dev/null || echo "0")
                improvement=$(echo "scale=1; ($current_total / $baseline_total - 1) * 100" | bc 2>/dev/null || echo "0")
                improvement="${improvement}%"
            else
                improvement="N/A"
            fi
        fi
        
        printf "%-19s | %9s | %9s | %11s | %s\n" "$config" "$set_rps" "$get_rps" "$pipeline_rps" "$improvement"
    fi
done < performance_comparison.csv

echo ""
echo "📈 **Key Optimizations Tested:**"
echo "• BASIC_IOURING: Standard io_uring with batch submission"
echo "• SQPOLL_IOURING: + Kernel-side polling (SQPOLL)"
echo "• ULTIMATE_IOURING: + Multi-shot accept + Fixed buffers"
echo ""
echo "🎯 **Target**: 1.5x improvement over epoll baseline (232K+ RPS total)"
echo ""

# Check if target achieved
if [ -f "performance_comparison.csv" ]; then
    best_total=$(tail -n +2 performance_comparison.csv | while IFS=',' read -r config set_rps get_rps pipeline_rps; do
        if [ "$config" != "EPOLL_BASELINE" ]; then
            total=$(echo "$set_rps + $get_rps" | bc 2>/dev/null || echo "0")
            echo "$total"
        fi
    done | sort -nr | head -1)
    
    if [ -n "$best_total" ] && [ -n "$baseline_total" ] && [ "$baseline_total" != "0" ]; then
        improvement_ratio=$(echo "scale=2; $best_total / $baseline_total" | bc 2>/dev/null || echo "0")
        if [ "$(echo "$improvement_ratio >= 1.5" | bc 2>/dev/null || echo "0")" = "1" ]; then
            echo "🎉 **TARGET ACHIEVED!** Best configuration: ${improvement_ratio}x improvement"
        else
            echo "⚠️  **Target not yet reached.** Best: ${improvement_ratio}x (need 1.5x)"
        fi
    fi
fi

echo ""
echo "📁 Results saved to: performance_comparison.csv"
echo "🏁 Advanced io_uring performance test completed!"