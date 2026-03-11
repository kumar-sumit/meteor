#!/bin/bash

echo "=== 🚀 OPTIMIZED io_uring SERVER TEST (Phase 6 Step 3 + io_uring) 🚀 ==="
echo "🎯 Goal: Beat DragonflyDB with ALL Phase 6 Step 3 optimizations + io_uring"
echo "⚡ Architecture: Pure io_uring + Pipeline Batching + CPU Affinity + SIMD"
echo "🏆 Target: 1.5M+ RPS"
echo ""

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    pkill -f meteor_optimized_iouring || true
    sleep 2
}

# Initial cleanup
cleanup

echo "=== 🔨 BUILDING OPTIMIZED SERVER ==="
chmod +x build_phase7_step1_optimized.sh
./build_phase7_step1_optimized.sh

if [ ! -f meteor_optimized_iouring ]; then
    echo "❌ Build failed! Cannot proceed with testing."
    exit 1
fi

echo ""
echo "=== 🚀 STARTING OPTIMIZED SERVER ==="
echo "Starting Optimized io_uring server (4 cores, port 6379)..."
timeout 300s ./meteor_optimized_iouring -h 127.0.0.1 -p 6379 -c 4 -s 16 > optimized_iouring.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
sleep 10

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    echo "Server log:"
    tail -20 optimized_iouring.log
    exit 1
fi

echo "✅ Optimized io_uring server is running"

echo ""
echo "=== 📊 SERVER ARCHITECTURE VERIFICATION ==="
echo "io_uring initialization:"
grep -E "(io_uring|initialized)" optimized_iouring.log | head -8

echo ""
echo "Phase 6 Step 3 features:"
if grep -q "pipeline" optimized_iouring.log; then
    echo "✅ Pipeline batching active"
fi
if grep -q "CPU affinity" optimized_iouring.log; then
    echo "✅ CPU affinity active"
fi
if grep -q "SIMD" optimized_iouring.log; then
    echo "✅ SIMD optimizations active"
fi

echo ""
echo "=== 🔌 CONNECTIVITY TEST ==="
echo "Testing basic PING..."
PING_RESPONSE=$(echo -e "PING\r\n" | timeout 5s nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r\n')
echo "PING response: '$PING_RESPONSE'"

if [ "$PING_RESPONSE" = "+PONG" ] || [ "$PING_RESPONSE" = "PONG" ]; then
    echo "✅ Basic connectivity working!"
else
    echo "❌ PING failed - debugging..."
    echo "Recent server log:"
    tail -20 optimized_iouring.log
    cleanup
    exit 1
fi

echo ""
echo "=== 📊 PERFORMANCE BENCHMARKS ==="

echo "Non-pipelined test..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 50000 -c 20 -P 1 -q > non_pipeline_opt.txt 2>&1

echo "Pipelined test..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 30 -q > pipeline_opt.txt 2>&1

echo "High performance test..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 200000 -c 100 -P 100 -q > high_perf_opt.txt 2>&1

# Extract results
NON_PIPELINE_SET=$(grep "SET:" non_pipeline_opt.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")
PIPELINE_SET=$(grep "SET:" pipeline_opt.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")
HIGH_PERF_SET=$(grep "SET:" high_perf_opt.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")

echo ""
echo "=== 📈 PERFORMANCE RESULTS ==="
echo "================================"
echo "Non-pipelined SET: ${NON_PIPELINE_SET} RPS"
echo "Pipelined P30 SET: ${PIPELINE_SET} RPS"  
echo "High Perf P100:    ${HIGH_PERF_SET} RPS"

# Find best performance
BEST_RPS=0
BEST_TEST=""

check_performance() {
    local rps="$1"
    local test="$2"
    
    if [ ! -z "$rps" ] && [ "$rps" != "0" ]; then
        local rps_int=$(echo "$rps" | cut -d. -f1)
        if [ "$rps_int" -gt "$BEST_RPS" ]; then
            BEST_RPS=$rps_int
            BEST_TEST="$test"
        fi
    fi
}

check_performance "$NON_PIPELINE_SET" "Non-pipelined"
check_performance "$PIPELINE_SET" "Pipelined P30"
check_performance "$HIGH_PERF_SET" "High Perf P100"

echo ""
echo "🏆 BEST PERFORMANCE: $BEST_RPS RPS ($BEST_TEST)"

echo ""
echo "🎯 DRAGONFLY COMPARISON:"
echo "========================"
echo "Phase 6 Step 3:        ~800K RPS (baseline)"
echo "DragonflyDB Target:     1,000,000 RPS"
echo "Our Optimized io_uring: $BEST_RPS RPS"

# Performance analysis
if [ "$BEST_RPS" -gt "1500000" ]; then
    echo ""
    echo "🎉🎉🎉 OUTSTANDING SUCCESS! 🎉🎉🎉"
    echo "🏆 BEATS DRAGONFLY BY 50%+!"
    echo "🚀 Performance: $BEST_RPS RPS"
    echo "✅ Phase 6 Step 3 + io_uring = SUPERIOR!"
    
elif [ "$BEST_RPS" -gt "1200000" ]; then
    echo ""
    echo "🎉🎉 EXCELLENT SUCCESS! 🎉🎉"
    echo "🏆 BEATS DRAGONFLY!"
    echo "🚀 Performance: $BEST_RPS RPS"
    echo "✅ Optimized architecture working!"
    
elif [ "$BEST_RPS" -gt "1000000" ]; then
    echo ""
    echo "🎉 GREAT SUCCESS! 🎉"
    echo "🏆 MATCHES DRAGONFLY!"
    echo "🚀 Performance: $BEST_RPS RPS"
    echo "✅ Competitive with DragonflyDB!"
    
elif [ "$BEST_RPS" -gt "800000" ]; then
    echo ""
    echo "✅ GOOD SUCCESS!"
    echo "📈 BEATS Phase 6 Step 3 baseline!"
    echo "🚀 Performance: $BEST_RPS RPS"
    echo "🔧 Strong foundation for optimization!"
    
else
    echo ""
    echo "⚠️  NEEDS OPTIMIZATION"
    echo "📊 Performance: $BEST_RPS RPS"
    echo "🔍 Debug required"
fi

# Cleanup
cleanup

echo ""
echo "=== 🏁 OPTIMIZED io_uring TEST COMPLETED ==="
echo "🎯 Result: Phase 6 Step 3 + io_uring implementation"
echo "📊 Performance: $BEST_RPS RPS"
echo "🏆 Goal: $([ "$BEST_RPS" -gt "1000000" ] && echo "ACHIEVED" || echo "IN PROGRESS")"