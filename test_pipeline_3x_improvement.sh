#!/bin/bash

echo "=== 🎯 PHASE 7 STEP 1: 3x PIPELINE IMPROVEMENT TEST 🎯 ==="
echo "📊 Target: Phase 6 Step 3 (800K RPS) → Phase 7 Step 1 (2.4M+ RPS)"
echo "🔧 Method: DragonflyDB-style pipeline batching with io_uring"
echo ""

# Kill any existing servers
pkill -f meteor || true
sleep 2

echo "Starting Enhanced DragonflyDB Pipeline Server..."
./meteor_phase7_dragonfly_pipeline -p 6379 -c 4 > pipeline_server.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
sleep 8

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Enhanced pipeline server is running"
    
    echo ""
    echo "=== 🔍 PIPELINE ARCHITECTURE VALIDATION ==="
    echo "Server initialization:"
    grep -i "initialized.*io_uring\|started.*io_uring" pipeline_server.log | head -4
    
    echo ""
    echo "=== 🚀 FOCUSED PIPELINE BENCHMARK ==="
    
    # Quick validation test
    echo ""
    echo "🔸 Quick validation (P1 baseline):"
    timeout 30s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 10000 -c 10 -P 1 -q > validation.txt 2>&1
    if [ -s validation.txt ]; then
        echo "Validation result:"
        cat validation.txt
        BASELINE_RPS=$(grep "SET:" validation.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        echo "🎯 Baseline SET: $BASELINE_RPS RPS"
    fi
    
    echo ""
    echo "🔸 Pipeline P10 (Expected: 5-10x baseline):"
    timeout 45s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 50000 -c 20 -P 10 -q > pipeline_10.txt 2>&1
    if [ -s pipeline_10.txt ]; then
        echo "Pipeline P10 result:"
        cat pipeline_10.txt
        P10_RPS=$(grep "SET:" pipeline_10.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$P10_RPS" ]; then
            echo "🎯 Pipeline P10 SET: $P10_RPS RPS"
            
            # Calculate improvement
            if [ ! -z "$BASELINE_RPS" ]; then
                IMPROVEMENT_P10=$(echo "scale=1; $P10_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
                echo "📈 P10 Improvement: ${IMPROVEMENT_P10}x over baseline"
            fi
        fi
    fi
    
    echo ""
    echo "🔸 Pipeline P30 (Expected: 10-20x baseline):"
    timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 100000 -c 50 -P 30 -q > pipeline_30.txt 2>&1
    if [ -s pipeline_30.txt ]; then
        echo "Pipeline P30 result:"
        cat pipeline_30.txt
        P30_RPS=$(grep "SET:" pipeline_30.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$P30_RPS" ]; then
            echo "🎯 Pipeline P30 SET: $P30_RPS RPS"
            
            # Calculate improvement
            if [ ! -z "$BASELINE_RPS" ]; then
                IMPROVEMENT_P30=$(echo "scale=1; $P30_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
                echo "📈 P30 Improvement: ${IMPROVEMENT_P30}x over baseline"
            fi
        fi
    fi
    
    echo ""
    echo "🔸 Pipeline P100 (Maximum throughput test):"
    timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 200000 -c 100 -P 100 -q > pipeline_100.txt 2>&1
    if [ -s pipeline_100.txt ]; then
        echo "Pipeline P100 result:"
        cat pipeline_100.txt
        P100_RPS=$(grep "SET:" pipeline_100.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$P100_RPS" ]; then
            echo "🎯 Pipeline P100 SET: $P100_RPS RPS"
            
            # Calculate improvement
            if [ ! -z "$BASELINE_RPS" ]; then
                IMPROVEMENT_P100=$(echo "scale=1; $P100_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
                echo "📈 P100 Improvement: ${IMPROVEMENT_P100}x over baseline"
            fi
        fi
    fi
    
    echo ""
    echo "=== 📊 PIPELINE PROCESSING ANALYSIS ==="
    echo "Pipeline batches processed:"
    grep -c "processing pipeline batch" pipeline_server.log 2>/dev/null || echo "0"
    
    echo "Commands in batches:"
    grep "processing pipeline batch" pipeline_server.log | head -5
    
    echo "Batch responses sent:"
    grep -c "sent pipeline batch" pipeline_server.log 2>/dev/null || echo "0"
    
    echo ""
    echo "=== 🏆 3x IMPROVEMENT ASSESSMENT ==="
    
    # Find highest RPS achieved
    HIGHEST_RPS=0
    BEST_PIPELINE=""
    
    if [ ! -z "$P10_RPS" ]; then
        P10_INT=$(echo "$P10_RPS" | cut -d. -f1)
        if [ "$P10_INT" -gt "$HIGHEST_RPS" ]; then
            HIGHEST_RPS=$P10_INT
            BEST_PIPELINE="P10"
        fi
    fi
    
    if [ ! -z "$P30_RPS" ]; then
        P30_INT=$(echo "$P30_RPS" | cut -d. -f1)
        if [ "$P30_INT" -gt "$HIGHEST_RPS" ]; then
            HIGHEST_RPS=$P30_INT
            BEST_PIPELINE="P30"
        fi
    fi
    
    if [ ! -z "$P100_RPS" ]; then
        P100_INT=$(echo "$P100_RPS" | cut -d. -f1)
        if [ "$P100_INT" -gt "$HIGHEST_RPS" ]; then
            HIGHEST_RPS=$P100_INT
            BEST_PIPELINE="P100"
        fi
    fi
    
    echo "🎯 Performance Summary:"
    echo "======================"
    echo "Phase 6 Step 3 Target: 800,000 RPS"
    echo "Phase 7 Step 1 Target: 2,400,000 RPS (3x improvement)"
    echo ""
    echo "Best Result: $HIGHEST_RPS RPS ($BEST_PIPELINE)"
    
    if [ "$HIGHEST_RPS" -gt "2400000" ]; then
        IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
        echo "🎉 SUCCESS: 3x TARGET ACHIEVED!"
        echo "🏆 Performance: $HIGHEST_RPS RPS"
        echo "📈 Improvement: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
        echo "✅ DragonflyDB-style pipeline architecture delivers!"
        
    elif [ "$HIGHEST_RPS" -gt "1600000" ]; then
        IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
        echo "🚀 EXCELLENT: 2x+ IMPROVEMENT!"
        echo "📊 Performance: $HIGHEST_RPS RPS"
        echo "📈 Improvement: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
        echo "🎯 Close to 3x target, architecture is highly effective!"
        
    elif [ "$HIGHEST_RPS" -gt "800000" ]; then
        IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
        echo "📈 GOOD: Significant improvement over Phase 6 Step 3"
        echo "📊 Performance: $HIGHEST_RPS RPS"
        echo "📈 Improvement: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
        echo "✅ Pipeline architecture shows clear benefits"
        
    else
        echo "📊 BASELINE: Performance needs optimization"
        echo "🔍 Current: $HIGHEST_RPS RPS"
        echo "💡 Pipeline batching may need tuning"
    fi
    
else
    echo "❌ Enhanced pipeline server failed to start"
    echo "Server log:"
    cat pipeline_server.log 2>/dev/null || echo "No log file"
fi

# Kill server
kill $SERVER_PID 2>/dev/null || true
sleep 2
kill -9 $SERVER_PID 2>/dev/null || true

echo ""
echo "=== 🎯 PHASE 7 STEP 1: 3x IMPROVEMENT TEST COMPLETED ==="
echo "🚀 DragonflyDB-style architecture with pipeline batching"
echo "📊 Target validation: 800K → 2.4M+ RPS (3x improvement)"