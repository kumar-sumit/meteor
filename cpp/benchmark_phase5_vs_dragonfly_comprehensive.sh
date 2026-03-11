#!/bin/bash

echo "🚀 COMPREHENSIVE PHASE 5 STEP 4A vs DRAGONFLY BENCHMARK"
echo "========================================================"
echo "VM: $(hostname) - $(nproc) cores, $(free -h | grep Mem | awk '{print $2}') RAM"
echo "Date: $(date)"
echo

# Configuration
PHASE5_SERVER="172.23.72.71"
PHASE5_PORT="6391"
DRAGONFLY_PORT="6380"
RESULTS_DIR="~/benchmark_results_$(date +%Y%m%d_%H%M%S)"

echo "📁 Creating results directory: $RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

# Stop any existing servers
echo "🛑 Stopping any existing servers..."
pkill -f dragonfly || true
pkill -f meteor || true
sleep 5

echo
echo "🔍 PHASE 1: DRAGONFLY SETUP AND LOCAL BENCHMARK"
echo "==============================================="

# Install DragonflyDB if not present
if ! command -v dragonfly &> /dev/null; then
    echo "📦 Installing DragonflyDB..."
    curl -fsSL https://www.dragonflydb.io/install.sh | bash
    if [ -f ./dragonfly ]; then
        sudo mv dragonfly /usr/local/bin/
        echo "✅ DragonflyDB installed successfully"
    else
        echo "❌ DragonflyDB installation failed"
        exit 1
    fi
else
    echo "✅ DragonflyDB already installed"
fi

echo "DragonflyDB version:"
dragonfly --version

# Start DragonflyDB
echo
echo "🚀 Starting DragonflyDB (Local)..."
echo "Configuration: Default multi-threaded, port $DRAGONFLY_PORT"
nohup dragonfly --port=$DRAGONFLY_PORT --logtostderr > "$RESULTS_DIR/dragonfly.log" 2>&1 &
DRAGONFLY_PID=$!
echo "DragonflyDB started with PID: $DRAGONFLY_PID"

echo "Waiting 15 seconds for DragonflyDB startup..."
sleep 15

# Verify DragonflyDB is running
echo "🔍 Verifying DragonflyDB status..."
if ps -p $DRAGONFLY_PID > /dev/null; then
    echo "✅ DragonflyDB process running"
    if ss -tlnp | grep :$DRAGONFLY_PORT; then
        echo "✅ DragonflyDB listening on port $DRAGONFLY_PORT"
    else
        echo "❌ DragonflyDB not listening on port $DRAGONFLY_PORT"
        echo "Log (last 20 lines):"
        tail -20 "$RESULTS_DIR/dragonfly.log"
        exit 1
    fi
else
    echo "❌ DragonflyDB process died"
    echo "Log (last 20 lines):"
    tail -20 "$RESULTS_DIR/dragonfly.log"
    exit 1
fi

echo
echo "📊 BENCHMARK 1: DRAGONFLY LOCAL PERFORMANCE"
echo "==========================================="

echo "🔧 Redis-benchmark test 1: Standard load"
echo "redis-benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT -t set,get -n 100000 -c 50 -d 100 -q" | tee -a "$RESULTS_DIR/commands.log"
redis-benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT -t set,get -n 100000 -c 50 -d 100 -q | tee "$RESULTS_DIR/dragonfly_redis_bench_1.txt"

echo
echo "🔧 Redis-benchmark test 2: Higher load"
echo "redis-benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT -t set,get -n 200000 -c 100 -d 100 -q" | tee -a "$RESULTS_DIR/commands.log"
redis-benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT -t set,get -n 200000 -c 100 -d 100 -q | tee "$RESULTS_DIR/dragonfly_redis_bench_2.txt"

echo
echo "🔧 Redis-benchmark test 3: Maximum load"
echo "redis-benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT -t set,get -n 300000 -c 150 -d 100 -q" | tee -a "$RESULTS_DIR/commands.log"
redis-benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT -t set,get -n 300000 -c 150 -d 100 -q | tee "$RESULTS_DIR/dragonfly_redis_bench_3.txt"

echo
echo "🔧 Memtier-benchmark test: 30-second sustained load"
echo "memtier_benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT --ratio=1:1 -c 50 --test-time=30 --distinct-client-seed --randomize" | tee -a "$RESULTS_DIR/commands.log"
memtier_benchmark -h 127.0.0.1 -p $DRAGONFLY_PORT --ratio=1:1 -c 50 --test-time=30 --distinct-client-seed --randomize > "$RESULTS_DIR/dragonfly_memtier.txt" 2>&1

echo
echo "🔍 PHASE 2: PHASE 5 STEP 4A NETWORK BENCHMARK"
echo "=============================================="

# Check Phase 5 server connectivity
echo "🔍 Checking Phase 5 server connectivity..."
if nc -zv $PHASE5_SERVER $PHASE5_PORT; then
    echo "✅ Phase 5 server accessible at $PHASE5_SERVER:$PHASE5_PORT"
    
    echo
    echo "📊 BENCHMARK 2: PHASE 5 STEP 4A NETWORK PERFORMANCE"
    echo "==================================================="
    
    echo "🔧 Redis-benchmark test 1: Standard load (Network)"
    echo "redis-benchmark -h $PHASE5_SERVER -p $PHASE5_PORT -t set,get -n 100000 -c 50 -d 100 -q" | tee -a "$RESULTS_DIR/commands.log"
    redis-benchmark -h $PHASE5_SERVER -p $PHASE5_PORT -t set,get -n 100000 -c 50 -d 100 -q | tee "$RESULTS_DIR/phase5_redis_bench_1.txt"
    
    echo
    echo "🔧 Redis-benchmark test 2: Higher load (Network)"
    echo "redis-benchmark -h $PHASE5_SERVER -p $PHASE5_PORT -t set,get -n 200000 -c 100 -d 100 -q" | tee -a "$RESULTS_DIR/commands.log"
    redis-benchmark -h $PHASE5_SERVER -p $PHASE5_PORT -t set,get -n 200000 -c 100 -d 100 -q | tee "$RESULTS_DIR/phase5_redis_bench_2.txt"
    
    echo
    echo "🔧 Redis-benchmark test 3: Maximum load (Network)"
    echo "redis-benchmark -h $PHASE5_SERVER -p $PHASE5_PORT -t set,get -n 300000 -c 150 -d 100 -q" | tee -a "$RESULTS_DIR/commands.log"
    redis-benchmark -h $PHASE5_SERVER -p $PHASE5_PORT -t set,get -n 300000 -c 150 -d 100 -q | tee "$RESULTS_DIR/phase5_redis_bench_3.txt"
    
    echo
    echo "🔧 Memtier-benchmark test: 30-second sustained load (Network)"
    echo "memtier_benchmark --server=$PHASE5_SERVER --port=$PHASE5_PORT --ratio=1:1 -c 50 --test-time=30 --distinct-client-seed --randomize" | tee -a "$RESULTS_DIR/commands.log"
    memtier_benchmark --server=$PHASE5_SERVER --port=$PHASE5_PORT --ratio=1:1 -c 50 --test-time=30 --distinct-client-seed --randomize > "$RESULTS_DIR/phase5_memtier.txt" 2>&1
    
else
    echo "❌ Phase 5 server not accessible at $PHASE5_SERVER:$PHASE5_PORT"
    echo "Skipping Phase 5 network benchmarks"
fi

echo
echo "🔍 PHASE 3: RESULTS ANALYSIS"
echo "============================"

# Parse and display results
echo "📊 PERFORMANCE COMPARISON SUMMARY"
echo "================================="

echo
echo "🐲 DRAGONFLY RESULTS:"
echo "===================="
if [ -f "$RESULTS_DIR/dragonfly_redis_bench_1.txt" ]; then
    echo "Redis-benchmark (50 clients):"
    grep -E "(SET|GET):" "$RESULTS_DIR/dragonfly_redis_bench_1.txt" | head -2
    echo
    echo "Redis-benchmark (100 clients):"
    grep -E "(SET|GET):" "$RESULTS_DIR/dragonfly_redis_bench_2.txt" | head -2
    echo
    echo "Redis-benchmark (150 clients):"
    grep -E "(SET|GET):" "$RESULTS_DIR/dragonfly_redis_bench_3.txt" | head -2
fi

if [ -f "$RESULTS_DIR/dragonfly_memtier.txt" ]; then
    echo
    echo "Memtier-benchmark:"
    grep -E "Totals.*ops/sec" "$RESULTS_DIR/dragonfly_memtier.txt" | head -1
fi

echo
echo "🚀 PHASE 5 STEP 4A RESULTS:"
echo "=========================="
if [ -f "$RESULTS_DIR/phase5_redis_bench_1.txt" ]; then
    echo "Redis-benchmark (50 clients, Network):"
    grep -E "(SET|GET):" "$RESULTS_DIR/phase5_redis_bench_1.txt" | head -2
    echo
    echo "Redis-benchmark (100 clients, Network):"
    grep -E "(SET|GET):" "$RESULTS_DIR/phase5_redis_bench_2.txt" | head -2
    echo
    echo "Redis-benchmark (150 clients, Network):"
    grep -E "(SET|GET):" "$RESULTS_DIR/phase5_redis_bench_3.txt" | head -2
fi

if [ -f "$RESULTS_DIR/phase5_memtier.txt" ]; then
    echo
    echo "Memtier-benchmark (Network):"
    grep -E "Totals.*ops/sec" "$RESULTS_DIR/phase5_memtier.txt" | head -1
fi

echo
echo "📈 COMPARATIVE ANALYSIS:"
echo "======================="
echo "• DragonflyDB: Multi-threaded, optimized for modern hardware"
echo "• Phase 5 Step 4A: 16-core sharded, SIMD-optimized, lock-free"
echo "• Network overhead: Phase 5 tested over network, DragonflyDB local"
echo "• Architecture: Both use different approaches to multi-core scaling"

echo
echo "📁 DETAILED RESULTS SAVED TO: $RESULTS_DIR"
echo "=============================================="
echo "Files created:"
ls -la "$RESULTS_DIR/"

echo
echo "🔧 Cleaning up..."
pkill -f dragonfly || true
sleep 2

echo "✅ Comprehensive benchmark completed!"
echo "Results directory: $RESULTS_DIR"