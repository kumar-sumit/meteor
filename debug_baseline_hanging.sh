#!/bin/bash

echo "=========================================="
echo "🔍 DEBUG: IS THE HANGING ISSUE IN BASELINE?"
echo "$(date): Testing original baseline vs TTL versions"
echo "=========================================="

# Test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== CLEANUP ==="
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== TEST 1: ORIGINAL WORKING BASELINE ==="
echo "🚀 Starting original baseline (meteor_final_correct)..."

if [ ! -f meteor_final_correct ]; then
    echo "❌ meteor_final_correct not found, trying to build from baseline source..."
    
    # Try to build original baseline
    g++ -std=c++20 -O2 -DNDEBUG -DBOOST_FIBER_NO_EXCEPTIONS -pthread \
        meteor_phase1_2b_syscall_reduction_single_command_fixed.cpp \
        -o meteor_baseline_test \
        -lboost_fiber -lboost_context -lboost_system -luring 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ Built baseline from source"
        nohup ./meteor_baseline_test -c 4 -s 4 > baseline_debug.log 2>&1 &
        BASELINE_PID=$!
    else
        echo "❌ Failed to build baseline"
        exit 1
    fi
else
    nohup ./meteor_final_correct -c 4 -s 4 > baseline_debug.log 2>&1 &
    BASELINE_PID=$!
fi

sleep 5

if ps -p $BASELINE_PID > /dev/null; then
    echo "✅ Baseline server started (PID: $BASELINE_PID)"
    
    echo "Testing baseline commands..."
    echo -n "Baseline PING: "
    timeout 3s redis-cli -p 6379 PING && echo "✅" || echo "❌ TIMEOUT"
    
    echo -n "Baseline SET: "
    timeout 3s redis-cli -p 6379 SET baseline_test baseline_value && echo "✅" || echo "❌ TIMEOUT"
    
    echo -n "Baseline GET: "
    BASELINE_GET=$(timeout 3s redis-cli -p 6379 GET baseline_test 2>/dev/null)
    if [ $? -eq 0 ] && [ "$BASELINE_GET" = "baseline_value" ]; then
        echo "✅ $BASELINE_GET (BASELINE GET WORKING!)"
        BASELINE_GET_OK=true
    else
        echo "❌ TIMEOUT/FAILED: '$BASELINE_GET' (BASELINE ALSO HANGS!)"
        BASELINE_GET_OK=false
    fi
    
    echo -n "Baseline DEL: "
    BASELINE_DEL=$(timeout 3s redis-cli -p 6379 DEL baseline_test 2>/dev/null)
    if [ $? -eq 0 ] && [ "$BASELINE_DEL" = "1" ]; then
        echo "✅ $BASELINE_DEL (BASELINE DEL WORKING!)"
        BASELINE_DEL_OK=true
    else
        echo "❌ TIMEOUT/FAILED: '$BASELINE_DEL' (BASELINE DEL ALSO HANGS!)"
        BASELINE_DEL_OK=false
    fi
    
    kill $BASELINE_PID 2>/dev/null || true
    sleep 2
else
    echo "❌ Baseline server failed to start"
    BASELINE_GET_OK=false
    BASELINE_DEL_OK=false
fi

echo ""
echo "=== TEST 2: TTL VERSION COMPARISON ==="
echo "🚀 Starting simple TTL version..."

nohup ./meteor_simple_ttl -c 4 -s 4 > ttl_debug.log 2>&1 &
TTL_PID=$!
sleep 5

if ps -p $TTL_PID > /dev/null; then
    echo "✅ TTL server started (PID: $TTL_PID)"
    
    echo "Testing TTL version commands..."
    echo -n "TTL PING: "
    timeout 3s redis-cli -p 6379 PING && echo "✅" || echo "❌ TIMEOUT"
    
    echo -n "TTL SET: "
    timeout 3s redis-cli -p 6379 SET ttl_test ttl_value && echo "✅" || echo "❌ TIMEOUT"
    
    echo -n "TTL GET: "
    TTL_GET=$(timeout 3s redis-cli -p 6379 GET ttl_test 2>/dev/null)
    if [ $? -eq 0 ] && [ "$TTL_GET" = "ttl_value" ]; then
        echo "✅ $TTL_GET (TTL GET WORKING!)"
        TTL_GET_OK=true
    else
        echo "❌ TIMEOUT/FAILED: '$TTL_GET' (TTL GET HANGS!)"
        TTL_GET_OK=false
    fi
    
    kill $TTL_PID 2>/dev/null || true
    sleep 2
else
    echo "❌ TTL server failed to start"
    TTL_GET_OK=false
fi

echo ""
echo "=========================================="
echo "🔍 HANGING ISSUE ANALYSIS"
echo "=========================================="

echo ""
echo "RESULTS COMPARISON:"
if [ "$BASELINE_GET_OK" = true ] && [ "$BASELINE_DEL_OK" = true ]; then
    echo "✅ BASELINE: GET/DEL working correctly"
    if [ "$TTL_GET_OK" = false ]; then
        echo "❌ TTL VERSION: Introduces hanging issue"
        echo ""
        echo "🔍 CONCLUSION: TTL implementation breaks GET/DEL commands"
        echo "   The issue is in the TTL-related changes, not the baseline"
        echo "   Need to identify exact changes causing the hanging"
    else
        echo "✅ TTL VERSION: Also working correctly"
        echo ""
        echo "🤔 CONCLUSION: Intermittent issue or environment-specific"
    fi
elif [ "$BASELINE_GET_OK" = false ]; then
    echo "❌ BASELINE: GET/DEL also hanging"
    echo ""
    echo "🔍 CONCLUSION: Fundamental issue in server environment"
    echo "   The problem is not in TTL implementation"
    echo "   Possible causes:"
    echo "   • VM environment issues"
    echo "   • Redis-cli connectivity issues"  
    echo "   • Server socket/connection handling"
    echo "   • Compilation/build environment problems"
else
    echo "⚠️ MIXED RESULTS: Need more investigation"
fi

echo ""
echo "DIAGNOSTIC LOGS:"
echo "Baseline server log (last 10 lines):"
tail -10 baseline_debug.log 2>/dev/null || echo "No baseline log"

echo ""
echo "TTL server log (last 10 lines):"
tail -10 ttl_debug.log 2>/dev/null || echo "No TTL log"

echo ""
echo "$(date): Baseline vs TTL hanging analysis complete!"

EOF












