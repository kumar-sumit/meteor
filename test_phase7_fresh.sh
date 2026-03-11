#!/bin/bash

echo "=== 🚀 PHASE 7 STEP 1 FRESH: Test & Benchmark 🚀 ==="
echo "📊 Testing fresh io_uring implementation based on Phase 6 Step 3"
echo "🎯 Goal: Both pipelined and non-pipelined modes working"
echo ""

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    pkill -f meteor_phase7_fresh || true
    sleep 2
}

# Initial cleanup
cleanup

echo "=== 🔨 BUILDING FRESH PHASE 7 STEP 1 ==="
chmod +x build_phase7_step1_fresh.sh
./build_phase7_step1_fresh.sh

if [ ! -f meteor_phase7_fresh ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "=== 🚀 STARTING SERVER ==="
echo "Starting Phase 7 Step 1 Fresh server (4 cores, port 6379)..."
timeout 300s ./meteor_phase7_fresh -p 6379 -c 4 -s 16 > phase7_fresh.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
sleep 8

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    echo "Server log:"
    tail -20 phase7_fresh.log
    exit 1
fi

echo "✅ Server is running"

echo ""
echo "=== 🔍 SERVER INITIALIZATION ==="
grep -E "(initialized|started|io_uring|epoll)" phase7_fresh.log | head -10

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
    tail -20 phase7_fresh.log
    cleanup
    exit 1
fi

echo ""
echo "=== 📊 NON-PIPELINED BENCHMARK ==="
echo "Testing without pipeline (P1)..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 50000 -c 20 -P 1 -q > non_pipeline.txt 2>&1

if [ -s non_pipeline.txt ]; then
    echo "Non-pipelined results:"
    cat non_pipeline.txt
    NON_PIPELINE_SET=$(grep "SET:" non_pipeline.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    echo "🎯 Non-pipelined SET: ${NON_PIPELINE_SET:-0} RPS"
else
    echo "❌ Non-pipelined test failed"
fi

echo ""
echo "=== 📊 PIPELINED BENCHMARK ==="
echo "Testing with pipeline (P30)..."
timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 30 -q > pipeline.txt 2>&1

if [ -s pipeline.txt ]; then
    echo "Pipelined results:"
    cat pipeline.txt
    PIPELINE_SET=$(grep "SET:" pipeline.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    echo "🎯 Pipelined SET: ${PIPELINE_SET:-0} RPS"
else
    echo "❌ Pipelined test failed"
fi

echo ""
echo "=== 📊 MEMTIER BENCHMARK TEST ==="
if command -v memtier_benchmark >/dev/null 2>&1; then
    echo "Testing with memtier-benchmark (pipeline)..."
    timeout 60s memtier_benchmark -s 127.0.0.1 -p 6379 -P 10 -c 20 -t 4 --ratio=1:1 -n 10000 --hide-histogram > memtier.txt 2>&1
    
    if [ -s memtier.txt ]; then
        echo "memtier-benchmark results:"
        grep -E "(Ops/sec|Latency)" memtier.txt | head -5
        MEMTIER_OPS=$(grep "Ops/sec" memtier.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        echo "🎯 memtier Ops/sec: ${MEMTIER_OPS:-0}"
    else
        echo "❌ memtier-benchmark test failed"
    fi
else
    echo "⚠️  memtier_benchmark not available"
fi

echo ""
echo "=== 🔍 IO_URING STATUS ==="
if grep -q "initialized io_uring" phase7_fresh.log; then
    echo "✅ io_uring is active"
    echo "io_uring operations:"
    grep -c "io_uring" phase7_fresh.log || echo "0"
else
    echo "⚠️  io_uring not active (using epoll fallback)"
fi

echo ""
echo "=== 📈 PERFORMANCE ANALYSIS ==="
echo "Summary:"
echo "========"
echo "Non-pipelined: ${NON_PIPELINE_SET:-0} RPS"
echo "Pipelined P30: ${PIPELINE_SET:-0} RPS"

if [ ! -z "$PIPELINE_SET" ] && [ ! -z "$NON_PIPELINE_SET" ]; then
    # Calculate improvement
    IMPROVEMENT=$(echo "scale=1; $PIPELINE_SET / $NON_PIPELINE_SET" | bc 2>/dev/null || echo "N/A")
    echo "Pipeline improvement: ${IMPROVEMENT}x"
fi

echo ""
echo "=== 🎯 FINAL VERDICT ==="

# Check if both modes work
BOTH_WORK=false
if [ ! -z "$NON_PIPELINE_SET" ] && [ ! -z "$PIPELINE_SET" ]; then
    NON_PIPELINE_INT=$(echo "$NON_PIPELINE_SET" | cut -d. -f1)
    PIPELINE_INT=$(echo "$PIPELINE_SET" | cut -d. -f1)
    
    if [ "$NON_PIPELINE_INT" -gt "10000" ] && [ "$PIPELINE_INT" -gt "100000" ]; then
        BOTH_WORK=true
    fi
fi

if [ "$BOTH_WORK" = true ]; then
    echo "✅✅✅ SUCCESS: Both pipelined and non-pipelined modes working!"
    echo "🎉 Phase 7 Step 1 Fresh implementation successful!"
    echo "📊 Non-pipelined: $NON_PIPELINE_SET RPS"
    echo "📊 Pipelined: $PIPELINE_SET RPS"
    echo "🚀 Ready for production!"
else
    echo "⚠️  Partial success - needs optimization"
    echo "Non-pipelined: ${NON_PIPELINE_SET:-FAILED} RPS"
    echo "Pipelined: ${PIPELINE_SET:-FAILED} RPS"
fi

# Cleanup
cleanup

echo ""
echo "=== 🏁 TEST COMPLETED ==="