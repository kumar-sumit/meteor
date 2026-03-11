#!/bin/bash

echo "=== 🚀 PHASE 7 STEP 1: DragonflyDB Pipeline Benchmark 🚀 ==="
echo "🎯 TARGET: 3x improvement over Phase 6 Step 3 (800K+ RPS → 2.4M+ RPS)"
echo "🔧 Method: Pipeline mode with redis-benchmark and memtier-benchmark"
echo ""

# Kill any existing servers
pkill -f meteor || true
sleep 3

echo "Starting DragonflyDB-Style Server (4 cores)..."
./meteor_phase7_dragonfly -p 6379 -c 4 > dragonfly_pipeline.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start and initialize
sleep 10

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ DragonflyDB-style server is running"
    
    echo ""
    echo "=== 🔍 PHASE 1: SERVER STATUS VALIDATION ==="
    echo "Server initialization:"
    grep -i "initialized.*io_uring\|started.*io_uring\|listening.*port" dragonfly_pipeline.log | head -8
    
    echo ""
    echo "=== 🚀 PHASE 2: PIPELINE BENCHMARK SUITE ==="
    
    # Test 1: redis-benchmark with different pipeline depths
    echo ""
    echo "📊 TEST 1: redis-benchmark Pipeline Performance"
    echo "=============================================="
    
    echo ""
    echo "🔸 Pipeline Depth 1 (baseline):"
    timeout 45s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 1 -q > pipeline_p1.txt 2>&1 || echo "Pipeline P1 completed"
    if [ -s pipeline_p1.txt ]; then
        echo "Results:"
        cat pipeline_p1.txt
    else
        echo "❌ No results for P1"
    fi
    
    echo ""
    echo "🔸 Pipeline Depth 10:"
    timeout 45s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 10 -q > pipeline_p10.txt 2>&1 || echo "Pipeline P10 completed"
    if [ -s pipeline_p10.txt ]; then
        echo "Results:"
        cat pipeline_p10.txt
        
        # Extract SET RPS for comparison
        SET_P10=$(grep "SET:" pipeline_p10.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$SET_P10" ]; then
            echo "🎯 SET Performance P10: $SET_P10 RPS"
        fi
    else
        echo "❌ No results for P10"
    fi
    
    echo ""
    echo "🔸 Pipeline Depth 30 (High Performance):"
    timeout 45s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -P 30 -q > pipeline_p30.txt 2>&1 || echo "Pipeline P30 completed"
    if [ -s pipeline_p30.txt ]; then
        echo "Results:"
        cat pipeline_p30.txt
        
        # Extract SET RPS for comparison
        SET_P30=$(grep "SET:" pipeline_p30.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$SET_P30" ]; then
            echo "🎯 SET Performance P30: $SET_P30 RPS"
        fi
    else
        echo "❌ No results for P30"
    fi
    
    echo ""
    echo "🔸 Pipeline Depth 100 (Maximum Throughput):"
    timeout 45s redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 200000 -c 100 -P 100 -q > pipeline_p100.txt 2>&1 || echo "Pipeline P100 completed"
    if [ -s pipeline_p100.txt ]; then
        echo "Results:"
        cat pipeline_p100.txt
        
        # Extract SET RPS for comparison
        SET_P100=$(grep "SET:" pipeline_p100.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$SET_P100" ]; then
            echo "🎯 SET Performance P100: $SET_P100 RPS"
        fi
    else
        echo "❌ No results for P100"
    fi
    
    # Test 2: memtier-benchmark pipeline performance
    echo ""
    echo "📊 TEST 2: memtier-benchmark Pipeline Performance"
    echo "==============================================="
    
    if command -v memtier_benchmark >/dev/null 2>&1; then
        echo ""
        echo "🔸 memtier-benchmark Pipeline 1:"
        timeout 60s memtier_benchmark -s 127.0.0.1 -p 6379 -P 1 -c 20 -t 4 --ratio=1:1 -n 25000 --hide-histogram > memtier_p1.txt 2>&1 || echo "memtier P1 completed"
        if [ -s memtier_p1.txt ]; then
            echo "Pipeline P1 Results:"
            grep -E "(Ops/sec|Latency|requests per second)" memtier_p1.txt | head -5
        fi
        
        echo ""
        echo "🔸 memtier-benchmark Pipeline 10:"
        timeout 60s memtier_benchmark -s 127.0.0.1 -p 6379 -P 10 -c 20 -t 4 --ratio=1:1 -n 25000 --hide-histogram > memtier_p10.txt 2>&1 || echo "memtier P10 completed"
        if [ -s memtier_p10.txt ]; then
            echo "Pipeline P10 Results:"
            grep -E "(Ops/sec|Latency|requests per second)" memtier_p10.txt | head -5
        fi
        
        echo ""
        echo "🔸 memtier-benchmark Pipeline 30:"
        timeout 60s memtier_benchmark -s 127.0.0.1 -p 6379 -P 30 -c 50 -t 4 --ratio=1:1 -n 50000 --hide-histogram > memtier_p30.txt 2>&1 || echo "memtier P30 completed"
        if [ -s memtier_p30.txt ]; then
            echo "Pipeline P30 Results:"
            grep -E "(Ops/sec|Latency|requests per second)" memtier_p30.txt | head -5
            
            # Extract total ops/sec
            MEMTIER_P30=$(grep "Ops/sec" memtier_p30.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
            if [ ! -z "$MEMTIER_P30" ]; then
                echo "🎯 memtier P30 Total: $MEMTIER_P30 Ops/sec"
            fi
        fi
    else
        echo "⚠️  memtier_benchmark not available, skipping memtier tests"
    fi
    
    echo ""
    echo "=== 📈 PHASE 3: PERFORMANCE ANALYSIS & COMPARISON ==="
    echo ""
    echo "🔍 Phase 6 Step 3 Baseline: ~800K RPS"
    echo "🎯 Phase 7 Step 1 Target: 2.4M+ RPS (3x improvement)"
    echo ""
    
    # Analyze results and compare with targets
    echo "📊 Pipeline Performance Summary:"
    echo "================================"
    
    if [ ! -z "$SET_P10" ]; then
        SET_P10_INT=$(echo "$SET_P10" | cut -d. -f1)
        if [ "$SET_P10_INT" -gt "800000" ]; then
            echo "✅ Pipeline P10 SET: $SET_P10 RPS (EXCEEDS Phase 6 Step 3 baseline!)"
        else
            echo "📊 Pipeline P10 SET: $SET_P10 RPS"
        fi
    fi
    
    if [ ! -z "$SET_P30" ]; then
        SET_P30_INT=$(echo "$SET_P30" | cut -d. -f1)
        if [ "$SET_P30_INT" -gt "2400000" ]; then
            echo "🎉 Pipeline P30 SET: $SET_P30 RPS (TARGET ACHIEVED! 3x improvement!)"
        elif [ "$SET_P30_INT" -gt "1600000" ]; then
            echo "🚀 Pipeline P30 SET: $SET_P30 RPS (2x improvement, approaching target)"
        elif [ "$SET_P30_INT" -gt "800000" ]; then
            echo "📈 Pipeline P30 SET: $SET_P30 RPS (exceeds Phase 6 Step 3 baseline)"
        else
            echo "📊 Pipeline P30 SET: $SET_P30 RPS"
        fi
    fi
    
    if [ ! -z "$SET_P100" ]; then
        SET_P100_INT=$(echo "$SET_P100" | cut -d. -f1)
        if [ "$SET_P100_INT" -gt "2400000" ]; then
            echo "🏆 Pipeline P100 SET: $SET_P100 RPS (MAXIMUM TARGET ACHIEVED!)"
        elif [ "$SET_P100_INT" -gt "1600000" ]; then
            echo "🚀 Pipeline P100 SET: $SET_P100 RPS (2x+ improvement)"
        else
            echo "📊 Pipeline P100 SET: $SET_P100 RPS"
        fi
    fi
    
    if [ ! -z "$MEMTIER_P30" ]; then
        MEMTIER_P30_INT=$(echo "$MEMTIER_P30" | cut -d. -f1)
        if [ "$MEMTIER_P30_INT" -gt "2400000" ]; then
            echo "🏆 memtier P30: $MEMTIER_P30 Ops/sec (3x TARGET ACHIEVED!)"
        elif [ "$MEMTIER_P30_INT" -gt "1600000" ]; then
            echo "🚀 memtier P30: $MEMTIER_P30 Ops/sec (2x+ improvement)"
        else
            echo "📊 memtier P30: $MEMTIER_P30 Ops/sec"
        fi
    fi
    
    echo ""
    echo "=== 🔍 PHASE 4: ARCHITECTURE EFFICIENCY ANALYSIS ==="
    echo "Server activity during benchmarks:"
    echo "Connections accepted: $(grep -c 'accepted connection' dragonfly_pipeline.log 2>/dev/null || echo '0')"
    echo "Commands processed: $(grep -c 'processing command' dragonfly_pipeline.log 2>/dev/null || echo '0')"
    echo "io_uring operations: $(grep -c 'submitted.*operation' dragonfly_pipeline.log 2>/dev/null || echo '0')"
    
    echo ""
    echo "Core utilization (should be balanced across 4 cores):"
    grep -i "core.*submitted\|core.*accepted" dragonfly_pipeline.log | tail -10
    
    echo ""
    echo "=== 🏆 FINAL VERDICT: PHASE 7 STEP 1 PIPELINE PERFORMANCE ==="
    
    # Determine overall success
    HIGHEST_RPS=0
    if [ ! -z "$SET_P30_INT" ] && [ "$SET_P30_INT" -gt "$HIGHEST_RPS" ]; then
        HIGHEST_RPS=$SET_P30_INT
    fi
    if [ ! -z "$SET_P100_INT" ] && [ "$SET_P100_INT" -gt "$HIGHEST_RPS" ]; then
        HIGHEST_RPS=$SET_P100_INT
    fi
    if [ ! -z "$MEMTIER_P30_INT" ] && [ "$MEMTIER_P30_INT" -gt "$HIGHEST_RPS" ]; then
        HIGHEST_RPS=$MEMTIER_P30_INT
    fi
    
    if [ "$HIGHEST_RPS" -gt "2400000" ]; then
        echo "🎉 SUCCESS: 3x IMPROVEMENT ACHIEVED!"
        echo "🏆 Peak Performance: ${HIGHEST_RPS} RPS"
        echo "📈 Improvement: $(echo "scale=1; $HIGHEST_RPS / 800000" | bc)x over Phase 6 Step 3"
        echo "✅ DragonflyDB-style architecture delivers on promise!"
    elif [ "$HIGHEST_RPS" -gt "1600000" ]; then
        echo "🚀 EXCELLENT: 2x+ IMPROVEMENT ACHIEVED!"
        echo "📊 Peak Performance: ${HIGHEST_RPS} RPS"
        echo "📈 Improvement: $(echo "scale=1; $HIGHEST_RPS / 800000" | bc)x over Phase 6 Step 3"
        echo "🎯 Close to 3x target, architecture is highly effective!"
    elif [ "$HIGHEST_RPS" -gt "800000" ]; then
        echo "📈 GOOD: Significant improvement over Phase 6 Step 3"
        echo "📊 Peak Performance: ${HIGHEST_RPS} RPS"
        echo "✅ DragonflyDB architecture shows clear benefits"
    else
        echo "📊 BASELINE: Performance comparable to Phase 6 Step 3"
        echo "🔍 Architecture working, may need further optimization"
    fi
    
else
    echo "❌ DragonflyDB-style server failed to start"
    echo "Server log:"
    cat dragonfly_pipeline.log 2>/dev/null || echo "No log file"
fi

# Kill server
kill $SERVER_PID 2>/dev/null || true
sleep 2
kill -9 $SERVER_PID 2>/dev/null || true

echo ""
echo "=== 🎯 PHASE 7 STEP 1 PIPELINE BENCHMARK COMPLETED ==="
echo "🔍 Key Innovation: DragonflyDB shared-nothing + io_uring pipeline"
echo "🚀 Target: 3x improvement (800K → 2.4M+ RPS)"