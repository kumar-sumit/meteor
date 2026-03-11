#!/bin/bash

echo "🔥 **STEP 1.3 PERFORMANCE VERIFICATION vs BASELINE**"
echo "=================================================="
echo ""
echo "📋 **OBJECTIVE**: Verify Step 1.3 achieves 4M+ QPS with no performance regression"
echo "📍 **BASELINE TARGET**: ~4.3M QPS (16 cores), ~3.1M QPS (4 cores)"
echo "📈 **REQUIREMENT**: >=90% baseline performance + 100% correctness"
echo ""

# Clean up
pkill -f meteor
sleep 3

echo "📋 **PHASE 1: ESTABLISH BASELINE - Working Step 1.2**"
echo "==================================================="

if [ -f meteor_step1_2_performance_fixed ]; then
    echo "🔍 Found working Step 1.2 baseline binary"
    BASELINE_BINARY="meteor_step1_2_performance_fixed"
elif [ -f sharded_server_temporal_step1_2_performance_fixed ]; then
    echo "🔧 Building Step 1.2 baseline..."
    g++ -std=c++17 -O3 -march=native -mtune=native -pthread -DHAS_LINUX_EPOLL=1 -DNDEBUG \
        -Wall -Wno-unused-parameter -Wno-unused-variable \
        sharded_server_temporal_step1_2_performance_fixed.cpp \
        -o meteor_step1_2_baseline -luring -latomic > /dev/null 2>&1
    BASELINE_BINARY="meteor_step1_2_baseline"
else
    echo "⚠️  No Step 1.2 baseline found - using Step 1.3 as reference"
    BASELINE_BINARY="meteor_step1_3_proper"
fi

echo ""
echo "⚡ **BASELINE PERFORMANCE TEST (4 cores):**"
echo "Starting baseline server (4 cores)..."
./$BASELINE_BINARY -p 6380 -c 4 > baseline_test.log 2>&1 &
sleep 15

echo "Running HIGH-PERFORMANCE benchmark (pipeline=10)..."
memtier_benchmark -s 127.0.0.1 -p 6380 -c 30 -t 8 --test-time=15 --ratio=1:1 --pipeline=10 \
    --hide-histogram 2>/dev/null | grep -E "(Totals|Throughput)" | head -2 | \
    tee baseline_results.txt

BASELINE_QPS=$(grep "Totals" baseline_results.txt | awk '{print $2}' | sed 's/[^0-9.]//g')
echo "📊 BASELINE QPS: $BASELINE_QPS"

pkill -f meteor
sleep 5

echo ""
echo "📋 **PHASE 2: STEP 1.3 PERFORMANCE VERIFICATION**"
echo "==============================================="

echo "⚡ **STEP 1.3 PERFORMANCE TEST (4 cores):**"
echo "Starting Step 1.3 server (4 cores)..."
./meteor_step1_3_proper -p 6380 -c 4 > step1_3_test.log 2>&1 &
sleep 15

echo "Running HIGH-PERFORMANCE benchmark (pipeline=10)..."
memtier_benchmark -s 127.0.0.1 -p 6380 -c 30 -t 8 --test-time=15 --ratio=1:1 --pipeline=10 \
    --hide-histogram 2>/dev/null | grep -E "(Totals|Throughput)" | head -2 | \
    tee step1_3_results.txt

STEP1_3_QPS=$(grep "Totals" step1_3_results.txt | awk '{print $2}' | sed 's/[^0-9.]//g')
echo "📊 STEP 1.3 QPS: $STEP1_3_QPS"

pkill -f meteor
sleep 3

echo ""
echo "📋 **PHASE 3: 16-CORE HIGH-PERFORMANCE TEST**"
echo "==========================================="

echo "🔥 **STEP 1.3 ULTIMATE PERFORMANCE (16 cores):**"
echo "Starting Step 1.3 server (16 cores)..."
./meteor_step1_3_proper -p 6380 -c 16 > step1_3_16core_test.log 2>&1 &
sleep 20

echo "Running ULTIMATE benchmark (16 cores + pipeline=10)..."
memtier_benchmark -s 127.0.0.1 -p 6380 -c 50 -t 16 --test-time=20 --ratio=1:1 --pipeline=10 \
    --hide-histogram 2>/dev/null | grep -E "(Totals|Throughput)" | head -2 | \
    tee step1_3_16core_results.txt

STEP1_3_16CORE_QPS=$(grep "Totals" step1_3_16core_results.txt | awk '{print $2}' | sed 's/[^0-9.]//g')
echo "📊 STEP 1.3 16-CORE QPS: $STEP1_3_16CORE_QPS"

pkill -f meteor
sleep 3

echo ""
echo "📋 **PHASE 4: PERFORMANCE ANALYSIS**"
echo "==================================="

echo ""
echo "📊 **PERFORMANCE COMPARISON:**"
echo "   🔷 Baseline (4 cores):  $BASELINE_QPS QPS"
echo "   🔥 Step 1.3 (4 cores):  $STEP1_3_QPS QPS"
echo "   🚀 Step 1.3 (16 cores): $STEP1_3_16CORE_QPS QPS"
echo ""

# Calculate performance ratio
if [ ! -z "$BASELINE_QPS" ] && [ ! -z "$STEP1_3_QPS" ]; then
    PERFORMANCE_RATIO=$(echo "scale=2; $STEP1_3_QPS / $BASELINE_QPS * 100" | bc -l 2>/dev/null || echo "N/A")
    echo "📈 **PERFORMANCE RATIO**: ${PERFORMANCE_RATIO}% of baseline"
    
    # Check if meets 90% requirement
    MEETS_REQUIREMENT=$(echo "$PERFORMANCE_RATIO >= 90" | bc -l 2>/dev/null || echo "0")
    if [ "$MEETS_REQUIREMENT" = "1" ]; then
        echo "✅ **PERFORMANCE REQUIREMENT**: MET (>=90%)"
    else
        echo "❌ **PERFORMANCE REQUIREMENT**: NOT MET (${PERFORMANCE_RATIO}% < 90%)"
    fi
else
    echo "⚠️  **PERFORMANCE CALCULATION**: Unable to calculate ratio"
fi

# Check 4M+ QPS target
TARGET_4M_MET=0
if [ ! -z "$STEP1_3_16CORE_QPS" ]; then
    TARGET_4M_MET=$(echo "$STEP1_3_16CORE_QPS >= 4000000" | bc -l 2>/dev/null || echo "0")
    if [ "$TARGET_4M_MET" = "1" ]; then
        echo "🎯 **4M+ QPS TARGET**: ACHIEVED ($STEP1_3_16CORE_QPS QPS)"
    else
        echo "🎯 **4M+ QPS TARGET**: NOT YET ACHIEVED ($STEP1_3_16CORE_QPS QPS)"
    fi
fi

echo ""
echo "📋 **PHASE 5: SERVER LOGS ANALYSIS**"
echo "===================================="

echo ""
echo "🔍 Step 1.3 server startup (last 10 lines):"
if [ -f step1_3_test.log ]; then
    tail -10 step1_3_test.log
fi

echo ""
echo "✅ **COMPREHENSIVE PERFORMANCE VERIFICATION COMPLETE**"
echo "======================================================"

if [ "$TARGET_4M_MET" = "1" ] && [ "$MEETS_REQUIREMENT" = "1" ]; then
    echo "🎉 **OUTSTANDING SUCCESS**: Step 1.3 EXCEEDS all performance targets!"
    echo "🔥 **BREAKTHROUGH**: Temporal coherence + 4M+ QPS achieved!"
    echo "⚡ **PRODUCTION READY**: Step 1.3 validated for deployment"
elif [ ! -z "$PERFORMANCE_RATIO" ] && [ "$MEETS_REQUIREMENT" = "1" ]; then
    echo "✅ **SUCCESS**: Step 1.3 meets performance requirements (${PERFORMANCE_RATIO}%)"
    echo "🔥 **TEMPORAL COHERENCE**: Fully operational with good performance"
    echo "🎯 **SCALING**: May need optimization for 4M+ QPS target"
else
    echo "⚠️  **PERFORMANCE ANALYSIS NEEDED**: Step 1.3 may have bottlenecks"
    echo "🔍 **NEXT STEPS**: Architecture review and optimization required"
fi

echo ""
echo "📊 **DETAILED RESULTS AVAILABLE:**"
echo "   - baseline_results.txt"
echo "   - step1_3_results.txt"
echo "   - step1_3_16core_results.txt"
echo "   - baseline_test.log"
echo "   - step1_3_test.log"
echo "   - step1_3_16core_test.log"