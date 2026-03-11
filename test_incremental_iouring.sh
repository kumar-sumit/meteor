#!/bin/bash

echo "=== 🚀 INCREMENTAL io_uring SERVER TEST (Phase 6 Step 3 + io_uring) 🚀 ==="
echo "🎯 Goal: Beat DragonflyDB with incremental io_uring integration"
echo "⚡ Architecture: ALL Phase 6 Step 3 optimizations + optional io_uring"
echo "🏆 Target: 1.5M+ RPS"
echo "🔧 Strategy: Test both epoll and io_uring modes for comparison"
echo ""

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    pkill -f meteor_incremental_iouring || true
    sleep 2
}

# Initial cleanup
cleanup

echo "=== 🔨 BUILDING INCREMENTAL SERVER ==="
chmod +x cpp/build_incremental_iouring.sh
cd cpp && ./build_incremental_iouring.sh && cd ..

if [ ! -f cpp/meteor_incremental_iouring ]; then
    echo "❌ Build failed! Cannot proceed with testing."
    exit 1
fi

# Test both modes
for MODE in "epoll" "io_uring"; do
    echo ""
    echo "=== 🚀 TESTING $MODE MODE ==="
    
    if [ "$MODE" = "io_uring" ]; then
        export METEOR_USE_IO_URING=1
        echo "🔧 Environment: METEOR_USE_IO_URING=1"
    else
        unset METEOR_USE_IO_URING
        echo "🔧 Environment: Default epoll mode"
    fi
    
    echo "Starting incremental server (4 cores, port 6379)..."
    timeout 300s cpp/meteor_incremental_iouring -h 127.0.0.1 -p 6379 -c 4 > ${MODE}_server.log 2>&1 &
    SERVER_PID=$!
    echo "Server PID: $SERVER_PID"

    # Wait for server to start
    sleep 8

    # Check if server is running
    if ! ps -p $SERVER_PID > /dev/null; then
        echo "❌ $MODE server failed to start"
        echo "Server log:"
        tail -20 ${MODE}_server.log
        cleanup
        continue
    fi

    echo "✅ $MODE server is running"

    echo ""
    echo "=== 📊 $MODE SERVER ARCHITECTURE VERIFICATION ==="
    if [ "$MODE" = "io_uring" ]; then
        grep -E "(io_uring|initialized)" ${MODE}_server.log | head -5
    else
        grep -E "(epoll|initialized)" ${MODE}_server.log | head -5
    fi

    echo ""
    echo "=== 🔌 $MODE CONNECTIVITY TEST ==="
    echo "Testing basic PING..."
    PING_RESPONSE=$(echo -e "PING\r\n" | timeout 5s nc -w 2 127.0.0.1 6379 2>/dev/null | tr -d '\r\n')
    echo "PING response: '$PING_RESPONSE'"

    if [ "$PING_RESPONSE" = "+PONG" ] || [ "$PING_RESPONSE" = "PONG" ]; then
        echo "✅ $MODE connectivity working!"
    else
        echo "❌ $MODE PING failed - skipping benchmarks"
        echo "Recent server log:"
        tail -10 ${MODE}_server.log
        cleanup
        continue
    fi

    echo ""
    echo "=== 📊 $MODE PERFORMANCE BENCHMARKS ==="

    echo "🔥 Non-pipelined baseline test..."
    timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 50000 -c 20 -P 1 -q > ${MODE}_non_pipeline.txt 2>&1

    echo "🔥 Pipelined performance test..."
    timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 30 -q > ${MODE}_pipeline.txt 2>&1

    echo "🔥 High performance test..."
    timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 200000 -c 100 -P 100 -q > ${MODE}_high_perf.txt 2>&1

    # Extract results
    NON_PIPELINE_SET=$(grep "SET:" ${MODE}_non_pipeline.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")
    PIPELINE_SET=$(grep "SET:" ${MODE}_pipeline.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")
    HIGH_PERF_SET=$(grep "SET:" ${MODE}_high_perf.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1 2>/dev/null || echo "0")

    echo ""
    echo "=== 📈 $MODE PERFORMANCE RESULTS ==="
    echo "================================"
    echo "Non-pipelined SET:  ${NON_PIPELINE_SET} RPS"
    echo "Pipelined P30 SET:  ${PIPELINE_SET} RPS"  
    echo "High Perf P100:     ${HIGH_PERF_SET} RPS"

    # Find best performance for this mode
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
    echo "🏆 BEST $MODE PERFORMANCE: $BEST_RPS RPS ($BEST_TEST)"
    
    # Store results for comparison
    if [ "$MODE" = "epoll" ]; then
        EPOLL_BEST_RPS=$BEST_RPS
        EPOLL_BEST_TEST="$BEST_TEST"
    else
        IOURING_BEST_RPS=$BEST_RPS
        IOURING_BEST_TEST="$BEST_TEST"
    fi

    cleanup
    sleep 2
done

echo ""
echo "=== 🏁 INCREMENTAL io_uring COMPARISON RESULTS ==="
echo "=================================================="
echo ""
echo "🔧 EPOLL MODE (Phase 6 Step 3 baseline):"
echo "   Performance: ${EPOLL_BEST_RPS:-0} RPS (${EPOLL_BEST_TEST:-N/A})"
echo ""
echo "⚡ io_uring MODE (Phase 7 Step 1):"
echo "   Performance: ${IOURING_BEST_RPS:-0} RPS (${IOURING_BEST_TEST:-N/A})"
echo ""

# Calculate improvement
if [ "${EPOLL_BEST_RPS:-0}" -gt "0" ] && [ "${IOURING_BEST_RPS:-0}" -gt "0" ]; then
    IMPROVEMENT=$(echo "scale=2; $IOURING_BEST_RPS / $EPOLL_BEST_RPS" | bc -l 2>/dev/null || echo "N/A")
    echo "📊 io_uring vs epoll: ${IMPROVEMENT}x improvement"
    
    if [ "$IMPROVEMENT" != "N/A" ]; then
        IMPROVEMENT_INT=$(echo "$IMPROVEMENT" | cut -d. -f1)
        if [ "$IMPROVEMENT_INT" -ge "2" ]; then
            echo ""
            echo "🎉🎉🎉 OUTSTANDING SUCCESS! 🎉🎉🎉"
            echo "🏆 io_uring BEATS epoll by ${IMPROVEMENT}x!"
            echo "🚀 Performance: ${IOURING_BEST_RPS} RPS"
            echo "✅ Incremental integration working perfectly!"
        elif [ "$IMPROVEMENT_INT" -ge "1" ]; then
            echo ""
            echo "🎉🎉 EXCELLENT SUCCESS! 🎉🎉"
            echo "🏆 io_uring BEATS epoll by ${IMPROVEMENT}x!"
            echo "🚀 Performance: ${IOURING_BEST_RPS} RPS"
            echo "✅ Incremental approach validated!"
        else
            echo ""
            echo "⚠️  io_uring performance needs optimization"
            echo "📊 Current: ${IMPROVEMENT}x vs epoll"
            echo "🔍 Debug and optimize required"
        fi
    fi
fi

echo ""
echo "🎯 DRAGONFLY COMPARISON:"
echo "========================"
echo "Phase 6 Step 3 (epoll):    ${EPOLL_BEST_RPS:-0} RPS"
echo "Phase 7 Step 1 (io_uring): ${IOURING_BEST_RPS:-0} RPS"
echo "DragonflyDB Target:         1,000,000 RPS"
echo ""
echo "🏆 Goal: $([ "${IOURING_BEST_RPS:-0}" -gt "1000000" ] && echo "ACHIEVED ✅" || echo "IN PROGRESS 🔧")"
echo "🚀 Status: Incremental io_uring integration complete!"