#!/bin/bash

echo "=========================================="
echo "🔍 DEBUGGING TTL+LRU HANGING ISSUE"
echo "$(date): Investigating GET/TTL command hangs"
echo "=========================================="

# Test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== STEP 1: CLEAN ENVIRONMENT ==="
pkill -f meteor 2>/dev/null || true
sleep 3

echo "=== STEP 2: START TTL SERVER WITH LOGGING ==="
echo "🚀 Starting meteor_ttl_lru_optimized..."
nohup ./meteor_ttl_lru_optimized -c 4 -s 4 > debug_ttl.log 2>&1 &
SERVER_PID=$!
sleep 5

echo "✅ Server started (PID: $SERVER_PID)"

echo ""
echo "=== STEP 3: SYSTEMATIC COMMAND TESTING ==="

echo "--- Test 1: PING (should work) ---"
timeout 5s redis-cli -p 6379 PING && echo "✅ PING: OK" || echo "❌ PING: TIMEOUT/FAILED"

echo "--- Test 2: SET (should work) ---"  
timeout 5s redis-cli -p 6379 SET test_key test_value && echo "✅ SET: OK" || echo "❌ SET: TIMEOUT/FAILED"

echo "--- Test 3: GET (hanging issue) ---"
timeout 5s redis-cli -p 6379 GET test_key && echo "✅ GET: OK" || echo "❌ GET: TIMEOUT/FAILED"

echo "--- Test 4: TTL (hanging issue) ---"
timeout 5s redis-cli -p 6379 TTL test_key && echo "✅ TTL: OK" || echo "❌ TTL: TIMEOUT/FAILED"

echo "--- Test 5: DEL (should work) ---"
timeout 5s redis-cli -p 6379 DEL test_key && echo "✅ DEL: OK" || echo "❌ DEL: TIMEOUT/FAILED"

echo ""
echo "=== STEP 4: SERVER STATUS ==="
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server still running"
    echo "Server connections:"
    netstat -an | grep :6379 || echo "No connections found"
    echo ""
    echo "Server log (last 20 lines):"
    tail -20 debug_ttl.log
else
    echo "❌ Server crashed"
    echo "Crash log:"
    tail -30 debug_ttl.log
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=== COMPARISON: WORKING BASELINE TEST ==="
echo "🔍 Testing original working baseline for comparison..."

nohup ./meteor_final_correct -c 4 -s 4 > debug_baseline.log 2>&1 &
BASELINE_PID=$!
sleep 5

if ps -p $BASELINE_PID > /dev/null; then
    echo "✅ Baseline server started (PID: $BASELINE_PID)"
    
    echo "Baseline GET test:"
    timeout 5s redis-cli -p 6379 SET baseline_key baseline_val >/dev/null 2>&1
    timeout 5s redis-cli -p 6379 GET baseline_key && echo "✅ Baseline GET: OK" || echo "❌ Baseline GET: TIMEOUT"
    
    kill $BASELINE_PID 2>/dev/null || true
    sleep 2
else
    echo "❌ Baseline server failed to start"
fi

echo ""
echo "=========================================="
echo "🔍 DEBUGGING SUMMARY"
echo "=========================================="
echo "$(date): TTL hanging debug complete"

EOF












