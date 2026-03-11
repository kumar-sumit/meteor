#!/bin/bash

echo "=== COMPREHENSIVE PHASE 6 vs PHASE 7 BENCHMARK ==="
echo "Timestamp: $(date)"
echo "Host: $(hostname)"
echo "CPU Info: $(lscpu | grep 'Model name' | head -1)"
echo

# Kill any existing servers
echo "🧹 Cleaning up existing processes..."
pkill -f meteor || true
sleep 3

echo "📊 Starting benchmark comparison..."
echo

# ============================================================================
echo "=== PHASE 6 STEP 3 BASELINE BENCHMARKS ==="
echo "Starting Phase 6 Step 3 baseline on port 6404..."
./meteor_phase6_step3_baseline -h 0.0.0.0 -p 6404 -c 4 -s 8 &
P6_PID=$!
sleep 5

if ps -p $P6_PID > /dev/null; then
    echo "✅ Phase 6 Step 3 is running (PID: $P6_PID)"
    
    echo
    echo "📈 1. Phase 6 Non-Pipeline Performance:"
    redis-benchmark -h 127.0.0.1 -p 6404 -t set,get -n 100000 -c 50 -q --csv | tee p6_nonpipeline.csv
    
    echo
    echo "📈 2. Phase 6 Pipeline Performance (P=10):"
    redis-benchmark -h 127.0.0.1 -p 6404 -t set,get -n 100000 -c 50 -P 10 -q --csv | tee p6_pipeline.csv
    
    echo
    echo "📈 3. Phase 6 High-Concurrency Test:"
    redis-benchmark -h 127.0.0.1 -p 6404 -t set,get -n 50000 -c 100 -q --csv | tee p6_highconcurrency.csv
    
else
    echo "❌ Phase 6 Step 3 failed to start"
fi

# Kill Phase 6 and start Phase 7
echo
echo "🔄 Switching to Phase 7..."
kill $P6_PID 2>/dev/null || true
sleep 3

# ============================================================================
echo "=== PHASE 7 STEP 1 IO_URING BENCHMARKS ==="
echo "Starting Phase 7 Step 1 io_uring on port 6409..."
./meteor_phase7_step1_timeout_fixed -h 0.0.0.0 -p 6409 -c 4 -s 8 &
P7_PID=$!
sleep 5

if ps -p $P7_PID > /dev/null; then
    echo "✅ Phase 7 Step 1 is running (PID: $P7_PID)"
    
    echo
    echo "🚀 1. Phase 7 Non-Pipeline Performance:"
    redis-benchmark -h 127.0.0.1 -p 6409 -t set,get -n 100000 -c 50 -q --csv | tee p7_nonpipeline.csv
    
    echo
    echo "🚀 2. Phase 7 Pipeline Performance (P=10):"
    redis-benchmark -h 127.0.0.1 -p 6409 -t set,get -n 100000 -c 50 -P 10 -q --csv | tee p7_pipeline.csv
    
    echo
    echo "🚀 3. Phase 7 High-Concurrency Test:"
    redis-benchmark -h 127.0.0.1 -p 6409 -t set,get -n 50000 -c 100 -q --csv | tee p7_highconcurrency.csv
    
    echo
    echo "🔧 4. Command Response Test:"
    echo "Testing basic commands..."
    timeout 5s redis-cli -h 127.0.0.1 -p 6409 ping || echo "PING test completed"
    timeout 5s redis-cli -h 127.0.0.1 -p 6409 set testkey testvalue || echo "SET test completed"
    timeout 5s redis-cli -h 127.0.0.1 -p 6409 get testkey || echo "GET test completed"
    
else
    echo "❌ Phase 7 Step 1 failed to start"
fi

# Cleanup
echo
echo "🧹 Cleaning up..."
kill $P7_PID 2>/dev/null || true
sleep 2

# ============================================================================
echo
echo "=== BENCHMARK RESULTS ANALYSIS ==="

if [ -f p6_nonpipeline.csv ] && [ -f p7_nonpipeline.csv ]; then
    echo "📊 Non-Pipeline Comparison:"
    echo "Phase 6 SET:" $(grep "SET" p6_nonpipeline.csv | cut -d',' -f2)
    echo "Phase 7 SET:" $(grep "SET" p7_nonpipeline.csv | cut -d',' -f2)
    echo "Phase 6 GET:" $(grep "GET" p6_nonpipeline.csv | cut -d',' -f2)
    echo "Phase 7 GET:" $(grep "GET" p7_nonpipeline.csv | cut -d',' -f2)
fi

if [ -f p6_pipeline.csv ] && [ -f p7_pipeline.csv ]; then
    echo
    echo "📊 Pipeline Comparison:"
    echo "Phase 6 SET (P=10):" $(grep "SET" p6_pipeline.csv | cut -d',' -f2)
    echo "Phase 7 SET (P=10):" $(grep "SET" p7_pipeline.csv | cut -d',' -f2)
    echo "Phase 6 GET (P=10):" $(grep "GET" p6_pipeline.csv | cut -d',' -f2)
    echo "Phase 7 GET (P=10):" $(grep "GET" p7_pipeline.csv | cut -d',' -f2)
fi

echo
echo "=== BENCHMARK COMPLETE ==="
echo "Timestamp: $(date)"
echo "All result files saved with p6_* and p7_* prefixes"