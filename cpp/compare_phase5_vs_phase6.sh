#!/bin/bash

# **Phase 5 vs Phase 6 Step 1 Comparison Test**
# Compare performance between Phase 5 and Phase 6 Step 1

echo "🔥 Phase 5 vs Phase 6 Step 1 Comparison Benchmark"
echo "=================================================="
echo "Testing both versions with identical configurations"
echo

# Kill any existing servers
pkill -f meteor 2>/dev/null || true
sleep 3

# Results file
RESULTS="phase5_vs_phase6_comparison.txt"
echo "Phase 5 vs Phase 6 Step 1 Comparison - $(date)" > $RESULTS
echo "================================================" >> $RESULTS
echo >> $RESULTS

# Test configuration
CORES=4
SHARDS=16
MEMORY=2048
THREADS=2
CONNECTIONS=5
REQUESTS=10000

echo "Test Configuration:"
echo "- Cores: $CORES"
echo "- Shards: $SHARDS" 
echo "- Memory: ${MEMORY}MB"
echo "- Benchmark: ${THREADS}t ${CONNECTIONS}c ${REQUESTS}n"
echo

# Test Phase 5 (if available)
if [ -f "./meteor_phase5_step4a_simd_lockfree_monitoring" ]; then
    echo "📊 Testing Phase 5 Step 4A..."
    echo "Phase 5 Step 4A Results:" >> $RESULTS
    echo "========================" >> $RESULTS
    
    ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6385 -c $CORES -s $SHARDS -m $MEMORY -l > phase5.log 2>&1 &
    PHASE5_PID=$!
    sleep 4
    
    if ps -p $PHASE5_PID > /dev/null; then
        echo "✅ Phase 5 server started"
        if timeout 10 memtier_benchmark -h 127.0.0.1 -p 6385 -t $THREADS -c $CONNECTIONS -n $REQUESTS --ratio=1:1 --hide-histogram 2>&1 | tee -a $RESULTS; then
            echo "✅ Phase 5 benchmark completed"
        else
            echo "❌ Phase 5 benchmark failed"
        fi
    else
        echo "❌ Phase 5 server failed to start"
        echo "Phase 5 startup failed" >> $RESULTS
    fi
    
    kill $PHASE5_PID 2>/dev/null || true
    echo >> $RESULTS
    sleep 2
else
    echo "⚠️ Phase 5 binary not found, skipping"
    echo "Phase 5 binary not found" >> $RESULTS
    echo >> $RESULTS
fi

# Test Phase 6 Step 1
echo "📊 Testing Phase 6 Step 1..."
echo "Phase 6 Step 1 Results:" >> $RESULTS
echo "=======================" >> $RESULTS

./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6386 -c $CORES -s $SHARDS -m $MEMORY -l > phase6.log 2>&1 &
PHASE6_PID=$!
sleep 4

if ps -p $PHASE6_PID > /dev/null; then
    echo "✅ Phase 6 server started"
    
    # Check if listening
    if ss -tlnp 2>/dev/null | grep :6386 > /dev/null; then
        echo "✅ Phase 6 server listening"
        
        if timeout 10 memtier_benchmark -h 127.0.0.1 -p 6386 -t $THREADS -c $CONNECTIONS -n $REQUESTS --ratio=1:1 --hide-histogram 2>&1 | tee -a $RESULTS; then
            echo "✅ Phase 6 benchmark completed"
        else
            echo "❌ Phase 6 benchmark failed"
        fi
    else
        echo "❌ Phase 6 server not listening"
        echo "Phase 6 server not listening" >> $RESULTS
    fi
else
    echo "❌ Phase 6 server failed to start"
    echo "Phase 6 startup failed" >> $RESULTS
fi

kill $PHASE6_PID 2>/dev/null || true
echo >> $RESULTS

echo
echo "📋 Server Startup Logs:"
echo "======================="
echo "Phase 5 Log (first 20 lines):"
head -20 phase5.log 2>/dev/null || echo "No Phase 5 log"
echo
echo "Phase 6 Log (first 20 lines):"
head -20 phase6.log 2>/dev/null || echo "No Phase 6 log"

echo
echo "🎉 Comparison test complete!"
echo "Results saved to: $RESULTS"
echo
echo "📊 Summary:"
cat $RESULTS