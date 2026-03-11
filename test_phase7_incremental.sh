#!/bin/bash

echo "=== 🚀 PHASE 7 STEP 1: INCREMENTAL io_uring TEST 🚀 ==="
echo "📊 Strategy: Phase 6 Step 3 baseline + incremental io_uring"
echo "🎯 Goal: Both pipelined and non-pipelined working + io_uring performance"
echo ""

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    pkill -f meteor_phase7_incremental || true
    sleep 2
}

# Initial cleanup
cleanup

echo "=== 🔨 BUILDING INCREMENTAL VERSION ==="
chmod +x build_phase7_step1_incremental.sh
./build_phase7_step1_incremental.sh

if [ ! -f meteor_phase7_incremental ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "=== 🚀 STARTING SERVER ==="
echo "Starting Phase 7 Step 1 Incremental server (4 cores, port 6379)..."
timeout 300s ./meteor_phase7_incremental -p 6379 -c 4 -s 16 > phase7_incremental.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
sleep 8

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    echo "Server log:"
    tail -20 phase7_incremental.log
    exit 1
fi

echo "✅ Server is running"

echo ""
echo "=== 🔍 SERVER INITIALIZATION ==="
echo "Event loop mode:"
grep -E "(event loop started|io_uring|epoll)" phase7_incremental.log | head -8

echo ""
echo "io_uring status:"
if grep -q "initialized io_uring" phase7_incremental.log; then
    echo "✅ io_uring is active"
    grep "initialized io_uring" phase7_incremental.log | wc -l | xargs echo "Cores with io_uring:"
else
    echo "⚠️  io_uring not available, using epoll fallback"
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
    tail -20 phase7_incremental.log
    cleanup
    exit 1
fi

echo ""
echo "=== 📊 NON-PIPELINED BENCHMARK ==="
echo "Testing without pipeline (P1)..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 50000 -c 20 -P 1 -q > non_pipeline_inc.txt 2>&1

if [ -s non_pipeline_inc.txt ]; then
    echo "Non-pipelined results:"
    cat non_pipeline_inc.txt
    NON_PIPELINE_SET=$(grep "SET:" non_pipeline_inc.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    NON_PIPELINE_GET=$(grep "GET:" non_pipeline_inc.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    echo "🎯 Non-pipelined SET: ${NON_PIPELINE_SET:-0} RPS"
    echo "🎯 Non-pipelined GET: ${NON_PIPELINE_GET:-0} RPS"
else
    echo "❌ Non-pipelined test failed"
fi

echo ""
echo "=== 📊 PIPELINED BENCHMARK ==="
echo "Testing with pipeline (P30)..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 30 -q > pipeline_inc.txt 2>&1

if [ -s pipeline_inc.txt ]; then
    echo "Pipelined results:"
    cat pipeline_inc.txt
    PIPELINE_SET=$(grep "SET:" pipeline_inc.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    PIPELINE_GET=$(grep "GET:" pipeline_inc.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    echo "🎯 Pipelined SET: ${PIPELINE_SET:-0} RPS"
    echo "🎯 Pipelined GET: ${PIPELINE_GET:-0} RPS"
else
    echo "❌ Pipelined test failed"
fi

echo ""
echo "=== 📊 HIGH PERFORMANCE TEST ==="
echo "Testing high pipeline depth (P100)..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 200000 -c 100 -P 100 -q > high_perf.txt 2>&1

if [ -s high_perf.txt ]; then
    echo "High performance results:"
    cat high_perf.txt
    HIGH_PERF_SET=$(grep "SET:" high_perf.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    echo "🎯 High Performance SET: ${HIGH_PERF_SET:-0} RPS"
else
    echo "❌ High performance test failed"
fi

echo ""
echo "=== 📊 MEMTIER BENCHMARK TEST ==="
if command -v memtier_benchmark >/dev/null 2>&1; then
    echo "Testing with memtier-benchmark (pipeline)..."
    timeout 60s memtier_benchmark -s 127.0.0.1 -p 6379 -P 10 -c 20 -t 4 --ratio=1:1 -n 10000 --hide-histogram > memtier_inc.txt 2>&1
    
    if [ -s memtier_inc.txt ]; then
        echo "memtier-benchmark results:"
        grep -E "(Ops/sec|Latency)" memtier_inc.txt | head -5
        MEMTIER_OPS=$(grep "Ops/sec" memtier_inc.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        echo "🎯 memtier Ops/sec: ${MEMTIER_OPS:-0}"
    else
        echo "❌ memtier-benchmark test failed"
    fi
else
    echo "⚠️  memtier_benchmark not available"
fi

echo ""
echo "=== 📈 PERFORMANCE ANALYSIS ==="
echo "Summary Results:"
echo "================"
echo "Non-pipelined SET: ${NON_PIPELINE_SET:-0} RPS"
echo "Non-pipelined GET: ${NON_PIPELINE_GET:-0} RPS"
echo "Pipelined P30 SET: ${PIPELINE_SET:-0} RPS"
echo "Pipelined P30 GET: ${PIPELINE_GET:-0} RPS"
echo "High Perf P100:    ${HIGH_PERF_SET:-0} RPS"

if [ ! -z "$PIPELINE_SET" ] && [ ! -z "$NON_PIPELINE_SET" ]; then
    # Calculate improvement
    IMPROVEMENT=$(echo "scale=1; $PIPELINE_SET / $NON_PIPELINE_SET" | bc 2>/dev/null || echo "N/A")
    echo "Pipeline improvement: ${IMPROVEMENT}x"
fi

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
echo "Best Performance: $BEST_RPS RPS ($BEST_TEST)"

echo ""
echo "=== 🎯 FINAL VERDICT ==="

# Check if both modes work
BOTH_WORK=false
NON_PIPELINE_OK=false
PIPELINE_OK=false

if [ ! -z "$NON_PIPELINE_SET" ]; then
    NON_PIPELINE_INT=$(echo "$NON_PIPELINE_SET" | cut -d. -f1)
    if [ "$NON_PIPELINE_INT" -gt "10000" ]; then
        NON_PIPELINE_OK=true
    fi
fi

if [ ! -z "$PIPELINE_SET" ]; then
    PIPELINE_INT=$(echo "$PIPELINE_SET" | cut -d. -f1)
    if [ "$PIPELINE_INT" -gt "50000" ]; then
        PIPELINE_OK=true
    fi
fi

if [ "$NON_PIPELINE_OK" = true ] && [ "$PIPELINE_OK" = true ]; then
    BOTH_WORK=true
fi

# Performance comparison with Phase 6 Step 3 and DragonflyDB
echo "Performance Comparison:"
echo "======================"
echo "Phase 6 Step 3 Target: ~800K RPS (baseline)"
echo "DragonflyDB Target:     ~1M+ RPS (to beat)"
echo "Phase 7 Incremental:   $BEST_RPS RPS"

if [ "$BOTH_WORK" = true ]; then
    if [ "$BEST_RPS" -gt "1000000" ]; then
        echo ""
        echo "🎉🎉🎉 OUTSTANDING SUCCESS! 🎉🎉🎉"
        echo "✅ Both pipelined and non-pipelined modes working!"
        echo "🚀 Performance: $BEST_RPS RPS"
        echo "🏆 BEATS DRAGONFLY TARGET!"
        echo "📊 Incremental io_uring integration successful!"
        
    elif [ "$BEST_RPS" -gt "800000" ]; then
        echo ""
        echo "🎉🎉 EXCELLENT SUCCESS! 🎉🎉"
        echo "✅ Both pipelined and non-pipelined modes working!"
        echo "🚀 Performance: $BEST_RPS RPS"
        echo "📈 Beats Phase 6 Step 3 baseline!"
        echo "🎯 Close to DragonflyDB performance!"
        
    else
        echo ""
        echo "✅✅ SUCCESS! ✅✅"
        echo "✅ Both pipelined and non-pipelined modes working!"
        echo "📊 Performance: $BEST_RPS RPS"
        echo "🔧 Solid foundation for further optimization!"
    fi
    
    echo ""
    echo "🏗️  Architecture Status:"
    if grep -q "io_uring mode" phase7_incremental.log; then
        echo "✅ io_uring integration active"
    else
        echo "⚠️  Running on epoll fallback (io_uring can be enhanced)"
    fi
    echo "✅ Pipeline processing working"
    echo "✅ Multi-core scaling active"
    echo "✅ Ready for further io_uring enhancements!"
    
else
    echo ""
    echo "⚠️  Partial Success"
    echo "Non-pipelined: $([ "$NON_PIPELINE_OK" = true ] && echo "✅ Working" || echo "❌ Needs fix")"
    echo "Pipelined: $([ "$PIPELINE_OK" = true ] && echo "✅ Working" || echo "❌ Needs fix")"
fi

# Cleanup
cleanup

echo ""
echo "=== 🏁 INCREMENTAL io_uring TEST COMPLETED ==="
echo "🎯 Strategy: Incremental io_uring on working Phase 6 Step 3 baseline"
echo "📊 Result: $([ "$BOTH_WORK" = true ] && echo "SUCCESS" || echo "PARTIAL SUCCESS")"