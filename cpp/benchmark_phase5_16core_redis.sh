#!/bin/bash

echo "🚀 PHASE 5 STEP 4A - 16 CORE REDIS-BENCHMARK TEST"
echo "================================================="
echo "Configuration: 16 cores, 16 shards, 1024MB memory"
echo "Baseline: Phase 5 achieved 165K RPS with 4-core config"
echo "Expected: ~4x improvement = 660K+ RPS with 16 cores"
echo

cd ~/meteor

echo "🔧 Stopping any running servers..."
pkill -f meteor || true
sleep 3

echo "🚀 Starting Phase 5 Step 4A with 16-core configuration..."
echo "Command: ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 16 -s 16 -m 1024 -l"
echo

# Start server in background
nohup ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 16 -s 16 -m 1024 -l > /tmp/phase5_16core.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting 15 seconds for server initialization..."
sleep 15

echo "🔍 Checking if server is running..."
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server is running"
    
    echo "🔍 Checking if port 6379 is listening..."
    if ss -tlnp | grep :6379; then
        echo "✅ Server is listening on port 6379"
        
        echo
        echo "📊 RUNNING REDIS-BENCHMARK TEST..."
        echo "=================================="
        echo "Test: SET and GET operations"
        echo "Requests: 100,000 each"
        echo "Clients: 50 concurrent"
        echo "Data size: 100 bytes"
        echo
        
        redis-benchmark -h 127.0.0.1 -p 6379 -t set,get -n 100000 -c 50 -d 100 -q
        
        echo
        echo "📈 PERFORMANCE ANALYSIS:"
        echo "======================="
        echo "• Previous Phase 5 (4-core): 165,289 RPS"
        echo "• Current Phase 5 (16-core): [See results above]"
        echo "• Expected improvement: ~4x (660K+ RPS)"
        echo
        
    else
        echo "❌ Server not listening on port 6379"
        echo "Server log:"
        tail -20 /tmp/phase5_16core.log
    fi
else
    echo "❌ Server process died"
    echo "Server log:"
    tail -20 /tmp/phase5_16core.log
fi

echo
echo "🔧 Cleaning up..."
pkill -f meteor || true
echo "✅ Test completed"