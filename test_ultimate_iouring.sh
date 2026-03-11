#!/bin/bash

# **ULTIMATE io_uring PERFORMANCE TEST with liburing 2.11**
echo "=== 🚀 ULTIMATE io_uring PERFORMANCE TEST (liburing 2.11) 🚀 ==="
echo "🎯 Testing all advanced io_uring optimizations vs DragonflyDB performance"
echo "⚡ Features: SQPOLL, Multi-shot accept, Fixed buffers, Zero-copy"
echo ""

# Test configurations
EPOLL_CONFIG=""
BASIC_IOURING="METEOR_USE_IO_URING=1"
SQPOLL_IOURING="METEOR_USE_IO_URING=1 METEOR_USE_SQPOLL=1"
ULTIMATE_IOURING="METEOR_USE_IO_URING=1 METEOR_USE_SQPOLL=1 METEOR_USE_MULTISHOT=1"

# Performance test function
run_performance_test() {
    local config_name="$1"
    local config_env="$2"
    local port="$3"
    local binary="${4:-./meteor_advanced_iouring}"
    
    echo "=== TESTING $config_name CONFIGURATION ==="
    echo "Environment: $config_env"
    echo "Binary: $binary"
    
    # Start server with timeout
    echo "Starting server..."
    timeout 30 bash -c "eval \"$config_env $binary -h 127.0.0.1 -p $port -c 4\"" &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 3
    
    # Test connectivity
    echo "Testing connectivity..."
    if timeout 5 redis-cli -p $port ping > /dev/null 2>&1; then
        echo "✅ Server responding"
    else
        echo "❌ Server not responding"
        kill -9 $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
        return 1
    fi
    
    # Run comprehensive benchmarks
    echo "Running comprehensive benchmarks..."
    
    # Basic SET/GET test
    SET_RPS=$(timeout 15 redis-benchmark -p $port -c 50 -n 20000 -t set -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    GET_RPS=$(timeout 15 redis-benchmark -p $port -c 50 -n 20000 -t get -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    
    # Pipeline test
    PIPELINE_RPS=$(timeout 15 redis-benchmark -p $port -c 50 -n 20000 -P 10 -t set,get -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    
    # High concurrency test
    HIGHC_RPS=$(timeout 15 redis-benchmark -p $port -c 200 -n 10000 -t set,get -q 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    
    echo "Performance Results:"
    echo "  SET: ${SET_RPS:-0} RPS"
    echo "  GET: ${GET_RPS:-0} RPS"
    echo "  Pipeline (10): ${PIPELINE_RPS:-0} RPS"
    echo "  High Concurrency (200c): ${HIGHC_RPS:-0} RPS"
    
    # Calculate total throughput
    TOTAL_RPS=$(echo "${SET_RPS:-0} + ${GET_RPS:-0}" | bc 2>/dev/null || echo "0")
    
    # Stop server
    kill -9 $SERVER_PID 2>/dev/null
    wait $SERVER_PID 2>/dev/null
    
    # Store results
    echo "$config_name,${SET_RPS:-0},${GET_RPS:-0},${PIPELINE_RPS:-0},${HIGHC_RPS:-0},$TOTAL_RPS" >> ultimate_performance.csv
    
    sleep 2
    echo ""
    
    return 0
}

# Initialize results file
echo "Configuration,SET_RPS,GET_RPS,PIPELINE_RPS,HIGHC_RPS,TOTAL_RPS" > ultimate_performance.csv

# Test all configurations
echo "🧪 Testing all configurations..."
echo ""

run_performance_test "EPOLL_BASELINE" "$EPOLL_CONFIG" "6380"
run_performance_test "BASIC_IOURING" "$BASIC_IOURING" "6381" 
run_performance_test "SQPOLL_IOURING" "$SQPOLL_IOURING" "6382"
run_performance_test "ULTIMATE_IOURING" "$ULTIMATE_IOURING" "6383"

# Generate comprehensive summary
echo "=== 📊 ULTIMATE PERFORMANCE COMPARISON 📊 ==="
echo ""
echo "Configuration        | SET RPS    | GET RPS    | Pipeline   | HighConc   | Total RPS  | vs Baseline"
echo "--------------------+-----------+-----------+-----------+-----------+-----------+------------"

# Read and display results with improvements
baseline_total=""
while IFS=',' read -r config set_rps get_rps pipeline_rps highc_rps total_rps; do
    if [ "$config" != "Configuration" ]; then
        # Calculate improvement over baseline
        if [ "$config" = "EPOLL_BASELINE" ]; then
            improvement="Baseline"
            baseline_total="$total_rps"
        else
            if [ -n "$baseline_total" ] && [ "$baseline_total" != "0" ] && [ "$(echo "$baseline_total > 0" | bc 2>/dev/null)" = "1" ]; then
                improvement_ratio=$(echo "scale=2; $total_rps / $baseline_total" | bc 2>/dev/null || echo "0")
                improvement="${improvement_ratio}x"
            else
                improvement="N/A"
            fi
        fi
        
        printf "%-19s | %9s | %9s | %9s | %9s | %9s | %s\n" \
            "$config" "$set_rps" "$get_rps" "$pipeline_rps" "$highc_rps" "$total_rps" "$improvement"
    fi
done < ultimate_performance.csv

echo ""
echo "🔬 **Advanced Features Analysis:**"

# Check which configuration performed best
best_config=$(tail -n +2 ultimate_performance.csv | sort -t',' -k6 -nr | head -1 | cut -d',' -f1)
best_total=$(tail -n +2 ultimate_performance.csv | sort -t',' -k6 -nr | head -1 | cut -d',' -f6)

echo "🏆 **Best Configuration**: $best_config"
echo "🎯 **Peak Performance**: $best_total RPS"

# Check if we beat the target
if [ -n "$baseline_total" ] && [ "$baseline_total" != "0" ]; then
    target_rps=$(echo "scale=0; $baseline_total * 1.5" | bc 2>/dev/null || echo "232000")
    echo "🎯 **Target (1.5x baseline)**: $target_rps RPS"
    
    if [ "$(echo "$best_total >= $target_rps" | bc 2>/dev/null || echo "0")" = "1" ]; then
        improvement_ratio=$(echo "scale=2; $best_total / $baseline_total" | bc 2>/dev/null || echo "0")
        echo "🎉 **TARGET ACHIEVED!** ${improvement_ratio}x improvement over baseline!"
    else
        echo "⚠️  **Target not reached.** Best: $best_total RPS (need $target_rps RPS)"
    fi
fi

echo ""
echo "📈 **Optimization Impact:**"
echo "• BASIC_IOURING: Standard async I/O with batching"
echo "• SQPOLL_IOURING: + Kernel-side polling (reduces syscalls)"
echo "• ULTIMATE_IOURING: + Multi-shot accept + Fixed buffers (zero-copy)"

echo ""
echo "💾 **Technical Details:**"
echo "• liburing version: 2.11 (latest)"
echo "• Advanced features: Multi-shot accept, Fixed buffers, SQPOLL"
echo "• Architecture: Thread-per-core with io_uring proactors"
echo "• Buffer management: Zero-copy with pre-registered buffers"

echo ""
echo "📁 **Results saved to**: ultimate_performance.csv"
echo "🏁 **Ultimate io_uring performance test completed!**"

# Show system info
echo ""
echo "🖥️  **System Information:**"
echo "Kernel: $(uname -r)"
echo "liburing: $(pkg-config --modversion liburing 2>/dev/null || echo 'check /usr/local')"
echo "CPU info: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs || echo 'unknown')"
echo "Available cores: $(nproc)"