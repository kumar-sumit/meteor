#!/bin/bash

echo "=== COMPREHENSIVE PHASE 7 STEP 1 TEST ==="
echo "Timestamp: $(date)"
echo

cd /dev/shm

# Kill any existing servers
echo "🧹 Cleaning up..."
pkill -f meteor || true
sleep 3

# Test Phase 7 Step 1
echo "=== PHASE 7 STEP 1 IO_URING TEST ==="
echo "Starting Phase 7 Step 1 diagnostic server..."
./meteor_phase7_diagnostic -h 0.0.0.0 -p 6409 -c 4 -s 8 &
P7_PID=$!
sleep 8

if ps -p $P7_PID > /dev/null; then
    echo "✅ Phase 7 Step 1 is running (PID: $P7_PID)"
    
    # Test basic connectivity
    echo "Testing port connectivity..."
    timeout 3s nc -z 127.0.0.1 6409 && echo "✅ Port 6409 is open" || echo "❌ Port not responding"
    
    # Test PING
    echo "Testing PING command..."
    timeout 5s redis-cli -h 127.0.0.1 -p 6409 ping > ping_result.txt 2>&1 || echo "PING test completed"
    echo "PING result: $(cat ping_result.txt)"
    
    # Test SET/GET
    echo "Testing SET/GET commands..."
    timeout 5s redis-cli -h 127.0.0.1 -p 6409 set testkey testvalue > set_result.txt 2>&1 || echo "SET test completed"
    timeout 5s redis-cli -h 127.0.0.1 -p 6409 get testkey > get_result.txt 2>&1 || echo "GET test completed"
    echo "SET result: $(cat set_result.txt)"
    echo "GET result: $(cat get_result.txt)"
    
    # Performance test
    echo "Testing Phase 7 Performance..."
    echo "1. Non-Pipeline Test:"
    timeout 30s redis-benchmark -h 127.0.0.1 -p 6409 -t set,get -n 50000 -c 20 -q --csv > p7_nonpipeline.csv 2>&1 || echo "Non-pipeline test completed"
    
    echo "2. Pipeline Test (P=5):"
    timeout 30s redis-benchmark -h 127.0.0.1 -p 6409 -t set,get -n 50000 -c 20 -P 5 -q --csv > p7_pipeline.csv 2>&1 || echo "Pipeline test completed"
    
    echo "3. High-Concurrency Test:"
    timeout 30s redis-benchmark -h 127.0.0.1 -p 6409 -t set,get -n 30000 -c 50 -q --csv > p7_highconcurrency.csv 2>&1 || echo "High-concurrency test completed"
    
else
    echo "❌ Phase 7 Step 1 failed to start or crashed"
fi

# Kill Phase 7
kill $P7_PID 2>/dev/null || true
sleep 3

# Results
echo
echo "=== PHASE 7 STEP 1 RESULTS ==="

if [ -f p7_nonpipeline.csv ]; then
    echo "📊 Non-Pipeline Results:"
    cat p7_nonpipeline.csv
    echo
fi

if [ -f p7_pipeline.csv ]; then
    echo "📊 Pipeline Results:"
    cat p7_pipeline.csv
    echo
fi

if [ -f p7_highconcurrency.csv ]; then
    echo "📊 High-Concurrency Results:"
    cat p7_highconcurrency.csv
    echo
fi

# Compare with Phase 6 baseline
echo "=== COMPARISON WITH PHASE 6 BASELINE ==="
if [ -f p6_pipeline.csv ]; then
    echo "Phase 6 Pipeline Results:"
    cat p6_pipeline.csv
    echo
fi

if [ -f p7_pipeline.csv ] && [ -f p6_pipeline.csv ]; then
    echo "📈 PERFORMANCE COMPARISON:"
    P6_SET=$(grep "SET" p6_pipeline.csv | cut -d',' -f2 | tr -d '"')
    P6_GET=$(grep "GET" p6_pipeline.csv | cut -d',' -f2 | tr -d '"')
    P7_SET=$(grep "SET" p7_pipeline.csv | cut -d',' -f2 | tr -d '"' 2>/dev/null || echo "0")
    P7_GET=$(grep "GET" p7_pipeline.csv | cut -d',' -f2 | tr -d '"' 2>/dev/null || echo "0")
    
    echo "Phase 6 SET: $P6_SET RPS"
    echo "Phase 7 SET: $P7_SET RPS"
    echo "Phase 6 GET: $P6_GET RPS" 
    echo "Phase 7 GET: $P7_GET RPS"
    
    if [ "$P7_SET" != "0" ] && [ "$P6_SET" != "0" ]; then
        IMPROVEMENT=$(echo "scale=2; $P7_SET / $P6_SET" | bc -l 2>/dev/null || echo "N/A")
        echo "🚀 SET Performance Improvement: ${IMPROVEMENT}x"
    fi
fi

echo
echo "=== TEST COMPLETE ==="
echo "Timestamp: $(date)"