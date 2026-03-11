#!/bin/bash

echo "=== 🚀 PHASE 7 STEP 1: FIXED PIPELINE 3x VALIDATION 🚀 ==="
echo "📊 Target: Phase 6 Step 3 (800K RPS) → Phase 7 Step 1 (2.4M+ RPS)"
echo "🔧 Fixed: Proper RESP parsing + Pipeline batching + DragonflyDB architecture"
echo ""

# Kill any existing servers
pkill -f meteor || true
sleep 3

echo "Starting Fixed DragonflyDB Pipeline Server (4 cores)..."
./meteor_phase7_fixed -p 6379 -c 4 > fixed_pipeline.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start and initialize io_uring
sleep 8

if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Fixed pipeline server is running"
    
    echo ""
    echo "=== 🔍 INITIALIZATION VALIDATION ==="
    echo "io_uring initialization:"
    grep -i "initialized.*io_uring\|started.*io_uring" fixed_pipeline.log | head -4
    
    # Quick connectivity test
    echo ""
    echo "🔸 Quick connectivity test:"
    echo -e "PING\r\n" | timeout 3s nc 127.0.0.1 6379 > connectivity_test.txt 2>&1 || true
    if [ -s connectivity_test.txt ]; then
        echo "Server response: $(cat connectivity_test.txt | tr -d '\r\n')"
    else
        echo "❌ No response to PING"
    fi
    
    echo ""
    echo "=== 🚀 PIPELINE PERFORMANCE TESTS ==="
    
    # Test 1: Baseline (P1) - Single command per request
    echo ""
    echo "🔸 Test 1: Baseline P1 (no pipeline):"
    timeout 30s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 50000 -c 20 -P 1 -q > baseline_p1.txt 2>&1
    if [ -s baseline_p1.txt ]; then
        echo "Baseline P1 result:"
        cat baseline_p1.txt
        BASELINE_RPS=$(grep "SET:" baseline_p1.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        echo "🎯 Baseline P1 SET: $BASELINE_RPS RPS"
    else
        echo "❌ Baseline test failed"
    fi
    
    # Test 2: Pipeline P10
    echo ""
    echo "🔸 Test 2: Pipeline P10 (Expected: 5-10x baseline):"
    timeout 45s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 100000 -c 30 -P 10 -q > pipeline_p10.txt 2>&1
    if [ -s pipeline_p10.txt ]; then
        echo "Pipeline P10 result:"
        cat pipeline_p10.txt
        P10_RPS=$(grep "SET:" pipeline_p10.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$P10_RPS" ]; then
            echo "🎯 Pipeline P10 SET: $P10_RPS RPS"
            if [ ! -z "$BASELINE_RPS" ]; then
                IMPROVEMENT_P10=$(echo "scale=1; $P10_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
                echo "📈 P10 Improvement: ${IMPROVEMENT_P10}x over baseline"
            fi
        fi
    else
        echo "❌ P10 test failed"
    fi
    
    # Test 3: Pipeline P30 (Target range)
    echo ""
    echo "🔸 Test 3: Pipeline P30 (Expected: 10-30x baseline, targeting 2.4M+):"
    timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 200000 -c 50 -P 30 -q > pipeline_p30.txt 2>&1
    if [ -s pipeline_p30.txt ]; then
        echo "Pipeline P30 result:"
        cat pipeline_p30.txt
        P30_RPS=$(grep "SET:" pipeline_p30.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$P30_RPS" ]; then
            echo "🎯 Pipeline P30 SET: $P30_RPS RPS"
            if [ ! -z "$BASELINE_RPS" ]; then
                IMPROVEMENT_P30=$(echo "scale=1; $P30_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
                echo "📈 P30 Improvement: ${IMPROVEMENT_P30}x over baseline"
            fi
        fi
    else
        echo "❌ P30 test failed"
    fi
    
    # Test 4: Pipeline P100 (Maximum throughput)
    echo ""
    echo "🔸 Test 4: Pipeline P100 (Maximum throughput test):"
    timeout 60s redis-benchmark -h 127.0.0.1 -p 6379 -t set -n 300000 -c 100 -P 100 -q > pipeline_p100.txt 2>&1
    if [ -s pipeline_p100.txt ]; then
        echo "Pipeline P100 result:"
        cat pipeline_p100.txt
        P100_RPS=$(grep "SET:" pipeline_p100.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$P100_RPS" ]; then
            echo "🎯 Pipeline P100 SET: $P100_RPS RPS"
            if [ ! -z "$BASELINE_RPS" ]; then
                IMPROVEMENT_P100=$(echo "scale=1; $P100_RPS / $BASELINE_RPS" | bc 2>/dev/null || echo "N/A")
                echo "📈 P100 Improvement: ${IMPROVEMENT_P100}x over baseline"
            fi
        fi
    else
        echo "❌ P100 test failed"
    fi
    
    echo ""
    echo "=== 📊 PIPELINE PROCESSING ANALYSIS ==="
    echo "RESP commands processed:"
    grep -c "processing RESP command" fixed_pipeline.log 2>/dev/null || echo "0"
    
    echo "Pipeline batches processed:"
    grep -c "processing pipeline batch" fixed_pipeline.log 2>/dev/null || echo "0"
    
    echo "Sample pipeline batches (showing command batching):"
    grep "processing pipeline batch" fixed_pipeline.log | head -5
    
    echo "Sample RESP command processing:"
    grep "processing RESP command: SET" fixed_pipeline.log | head -3
    
    echo ""
    echo "=== 🏆 3x IMPROVEMENT VALIDATION ==="
    
    # Find the highest RPS achieved
    HIGHEST_RPS=0
    BEST_TEST=""
    
    if [ ! -z "$P10_RPS" ]; then
        P10_INT=$(echo "$P10_RPS" | cut -d. -f1)
        if [ "$P10_INT" -gt "$HIGHEST_RPS" ]; then
            HIGHEST_RPS=$P10_INT
            BEST_TEST="P10"
        fi
    fi
    
    if [ ! -z "$P30_RPS" ]; then
        P30_INT=$(echo "$P30_RPS" | cut -d. -f1)
        if [ "$P30_INT" -gt "$HIGHEST_RPS" ]; then
            HIGHEST_RPS=$P30_INT
            BEST_TEST="P30"
        fi
    fi
    
    if [ ! -z "$P100_RPS" ]; then
        P100_INT=$(echo "$P100_RPS" | cut -d. -f1)
        if [ "$P100_INT" -gt "$HIGHEST_RPS" ]; then
            HIGHEST_RPS=$P100_INT
            BEST_TEST="P100"
        fi
    fi
    
    echo "🎯 FINAL PERFORMANCE ASSESSMENT:"
    echo "================================="
    echo "Phase 6 Step 3 Target:     800,000 RPS"
    echo "Phase 7 Step 1 Target:   2,400,000 RPS (3x improvement)"
    echo ""
    echo "Best Result: $HIGHEST_RPS RPS ($BEST_TEST pipeline)"
    
    if [ "$HIGHEST_RPS" -gt "2400000" ]; then
        IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
        echo ""
        echo "🎉🎉🎉 SUCCESS: 3x TARGET ACHIEVED! 🎉🎉🎉"
        echo "🏆 Peak Performance: $HIGHEST_RPS RPS"
        echo "📈 Improvement Factor: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
        echo "✅ DragonflyDB architecture + Fixed pipeline = SUCCESS!"
        echo "🚀 io_uring potential FULLY UNLOCKED!"
        
    elif [ "$HIGHEST_RPS" -gt "1600000" ]; then
        IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
        echo ""
        echo "🚀🚀 EXCELLENT: 2x+ IMPROVEMENT! 🚀🚀"
        echo "📊 Peak Performance: $HIGHEST_RPS RPS"
        echo "📈 Improvement Factor: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
        echo "🎯 Very close to 3x target - architecture is highly effective!"
        echo "✅ Major performance breakthrough achieved!"
        
    elif [ "$HIGHEST_RPS" -gt "800000" ]; then
        IMPROVEMENT_FACTOR=$(echo "scale=1; $HIGHEST_RPS / 800000" | bc)
        echo ""
        echo "📈 GOOD: Significant improvement over Phase 6 Step 3"
        echo "📊 Peak Performance: $HIGHEST_RPS RPS"
        echo "📈 Improvement Factor: ${IMPROVEMENT_FACTOR}x over Phase 6 Step 3"
        echo "✅ Fixed pipeline architecture shows clear benefits"
        
    else
        echo ""
        echo "📊 NEEDS OPTIMIZATION: Performance below expectations"
        echo "🔍 Current Peak: $HIGHEST_RPS RPS"
        echo "💡 Pipeline processing may need further tuning"
        echo "🔧 Check server logs for issues"
    fi
    
    # Additional GET test for completeness
    echo ""
    echo "🔸 Bonus Test: GET Pipeline P30:"
    timeout 30s redis-benchmark -h 127.0.0.1 -p 6379 -t get -n 100000 -c 50 -P 30 -q > get_p30.txt 2>&1
    if [ -s get_p30.txt ]; then
        echo "GET P30 result:"
        cat get_p30.txt
        GET_P30_RPS=$(grep "GET:" get_p30.txt | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ ! -z "$GET_P30_RPS" ]; then
            echo "🎯 GET P30: $GET_P30_RPS RPS"
        fi
    fi
    
else
    echo "❌ Fixed pipeline server failed to start"
    echo "Server log:"
    cat fixed_pipeline.log 2>/dev/null || echo "No log file"
fi

# Kill server
kill $SERVER_PID 2>/dev/null || true
sleep 2
kill -9 $SERVER_PID 2>/dev/null || true

echo ""
echo "=== 🎯 PHASE 7 STEP 1: FIXED PIPELINE VALIDATION COMPLETED ==="
echo "🔧 Key Fixes: RESP parsing + Pipeline batching + DragonflyDB architecture"
echo "🚀 Target: 3x improvement validation (800K → 2.4M+ RPS)"
echo "📊 Architecture: Thread-per-core + io_uring + Shared-nothing"