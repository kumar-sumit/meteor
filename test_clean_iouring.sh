#!/bin/bash

echo "=== 🚀 CLEAN io_uring SERVER TEST (Phase 7 Step 1) 🚀 ==="
echo "🎯 Goal: Beat DragonflyDB with clean io_uring implementation"
echo "⚡ Architecture: Pure io_uring + Phase 6 Step 3 optimizations"
echo "🏆 Target: 1.5M+ RPS"
echo ""

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    pkill -f meteor_clean_iouring || true
    sleep 2
}

# Initial cleanup
cleanup

echo "=== 🔨 BUILDING CLEAN SERVER ==="
chmod +x build_clean_iouring.sh
./build_clean_iouring.sh

if [ ! -f meteor_clean_iouring ]; then
    echo "❌ Build failed! Cannot proceed with testing."
    exit 1
fi

echo ""
echo "=== 🚀 STARTING CLEAN io_uring SERVER ==="
echo "Starting clean io_uring server (4 cores, port 6379)..."
timeout 300s ./meteor_clean_iouring -h 127.0.0.1 -p 6379 -c 4 > clean_iouring.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
sleep 8

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    echo "Server log:"
    tail -20 clean_iouring.log
    exit 1
fi

echo "✅ Clean io_uring server is running"

echo ""
echo "=== 📊 SERVER ARCHITECTURE VERIFICATION ==="
echo "io_uring initialization:"
grep -E "(io_uring|initialized)" clean_iouring.log | head -8

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
    tail -20 clean_iouring.log
    cleanup
    exit 1
fi

echo ""
echo "=== 📊 PERFORMANCE BENCHMARKS ==="

echo "🔥 Non-pipelined baseline test..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 50000 -c 20 -P 1 -q > non_pipeline_clean.txt 2>&1

echo "🔥 Pipelined performance test..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 30 -q > pipeline_clean.txt 2>&1

echo "🔥 High performance test..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 200000 -c 100 -P 100 -q > high_perf_clean.txt 2>&1

echo "🔥 Ultra performance test (DragonflyDB comparison)..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 500000 -c 200 -P 200 -q > ultra_perf_clean.txt 2>&1

# Extract results
NON_PIPELINE_SET=$(grep "SET:" non_pipeline_clean.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")
PIPELINE_SET=$(grep "SET:" pipeline_clean.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")
HIGH_PERF_SET=$(grep "SET:" high_perf_clean.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")
ULTRA_PERF_SET=$(grep "SET:" ultra_perf_clean.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")

echo ""
echo "=== 📈 PERFORMANCE RESULTS ==="
echo "================================"
echo "Non-pipelined SET:  ${NON_PIPELINE_SET} RPS"
echo "Pipelined P30 SET:  ${PIPELINE_SET} RPS"  
echo "High Perf P100:     ${HIGH_PERF_SET} RPS"
echo "Ultra Perf P200:    ${ULTRA_PERF_SET} RPS"

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
check_performance "$ULTRA_PERF_SET" "Ultra Perf P200"

echo ""
echo "🏆 BEST PERFORMANCE: $BEST_RPS RPS ($BEST_TEST)"

echo ""
echo "🎯 DRAGONFLY COMPARISON:"
echo "========================"
echo "Phase 6 Step 3:        ~800,000 RPS (baseline)"
echo "DragonflyDB Target:   1,000,000 RPS"
echo "Our Clean io_uring:     $BEST_RPS RPS"

# Performance analysis
if [ "$BEST_RPS" -gt "1500000" ]; then
    echo ""
    echo "🎉🎉🎉 OUTSTANDING SUCCESS! 🎉🎉🎉"
    echo "🏆 BEATS DRAGONFLY BY 50%+!"
    echo "🚀 Performance: $BEST_RPS RPS"
    echo "✅ Clean io_uring implementation = SUPERIOR!"
    
elif [ "$BEST_RPS" -gt "1200000" ]; then
    echo ""
    echo "🎉🎉 EXCELLENT SUCCESS! 🎉🎉"
    echo "🏆 BEATS DRAGONFLY!"
    echo "🚀 Performance: $BEST_RPS RPS"
    echo "✅ Clean architecture working perfectly!"
    
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
    echo "🔧 Strong foundation, ready for optimization!"
    
else
    echo ""
    echo "⚠️  NEEDS OPTIMIZATION"
    echo "📊 Performance: $BEST_RPS RPS"
    echo "🔍 Debug and optimize required"
fi

echo ""
echo "=== 🧪 MEMTIER BENCHMARK TEST ==="
echo "Testing with memtier-benchmark for pipelined workload..."

if command -v memtier_benchmark >/dev/null 2>&1; then
    echo "Running memtier-benchmark test..."
    timeout 60s memtier_benchmark -s 127.0.0.1 -p 6379 -P 30 -c 50 -n 10000 --hide-histogram > memtier_clean.txt 2>&1
    
    MEMTIER_RPS=$(grep "Totals" memtier_clean.txt | awk '{print $2}' | head -1 2>/dev/null || echo "0")
    echo "Memtier RPS: ${MEMTIER_RPS}"
    
    if [ ! -z "$MEMTIER_RPS" ] && [ "$MEMTIER_RPS" != "0" ]; then
        echo "✅ Memtier benchmark successful: ${MEMTIER_RPS} RPS"
    else
        echo "⚠️  Memtier benchmark had issues"
    fi
else
    echo "ℹ️  memtier_benchmark not available, skipping"
fi

# Cleanup
cleanup

echo ""
echo "=== 🏁 CLEAN io_uring TEST COMPLETED ==="
echo "🎯 Result: Clean io_uring implementation"
echo "📊 Performance: $BEST_RPS RPS"
echo "🏆 Goal: $([ "$BEST_RPS" -gt "1000000" ] && echo "ACHIEVED ✅" || echo "IN PROGRESS 🔧")"
echo "🚀 Status: Ready for production optimization!"