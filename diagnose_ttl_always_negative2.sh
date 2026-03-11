#!/bin/bash

echo "🔍 DIAGNOSING WHY TTL ALWAYS RETURNS -2"
echo "======================================="
echo ""
echo "Possible causes:"
echo "1. Keys not being found (routing to wrong core/cache)"
echo "2. Keys always treated as expired" 
echo "3. Logic error in TTL method"
echo ""

# Create diagnostic commands for VM
cat > /tmp/ttl_diagnostic_commands.txt << 'EOF'
# ===== TTL DIAGNOSTIC COMMANDS FOR VM =====

# Step 1: SSH to VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>"

# Step 2: Build and start server
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true && sleep 3

g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 -pthread -o meteor_debug meteor_commercial_lru_ttl_routing_consistent.cpp -luring

./meteor_debug -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &
SERVER_PID=$!
sleep 5

# Step 3: Basic connectivity test
redis-cli -p 6379 ping

# Step 4: Diagnostic tests
redis-cli -p 6379 flushall

echo ""
echo "🔍 DIAGNOSTIC TEST 1: Check if keys are being stored at all"
echo "=========================================================="

redis-cli -p 6379 set diagnostic_key_1 "test value 1"
GET_RESULT=$(redis-cli -p 6379 get diagnostic_key_1)
echo "SET diagnostic_key_1 -> GET result: '$GET_RESULT'"

if [ "$GET_RESULT" = "test value 1" ]; then
    echo "✅ SET and GET working - key storage OK"
    
    # Now test TTL
    TTL_RESULT=$(redis-cli -p 6379 ttl diagnostic_key_1)
    echo "TTL diagnostic_key_1 -> $TTL_RESULT"
    
    if [ "$TTL_RESULT" = "-1" ]; then
        echo "✅ TTL working correctly! Problem was routing consistency."
    elif [ "$TTL_RESULT" = "-2" ]; then
        echo "❌ TTL returning -2 even though key exists!"
        echo "🐛 ISSUE: TTL method can't find key that GET can find"
        echo "   → Different cache instances or routing still broken"
    else
        echo "❓ Unexpected TTL result: $TTL_RESULT"
    fi
else
    echo "❌ GET not working - key not stored properly"
    echo "🐛 ISSUE: SET command failing completely"
fi

echo ""
echo "🔍 DIAGNOSTIC TEST 2: Test key with TTL"
echo "======================================"

redis-cli -p 6379 set diagnostic_key_2 "expires soon" EX 300
GET_RESULT_2=$(redis-cli -p 6379 get diagnostic_key_2)
echo "SET diagnostic_key_2 EX 300 -> GET result: '$GET_RESULT_2'"

if [ "$GET_RESULT_2" = "expires soon" ]; then
    echo "✅ SET EX and GET working"
    
    TTL_RESULT_2=$(redis-cli -p 6379 ttl diagnostic_key_2)
    echo "TTL diagnostic_key_2 -> $TTL_RESULT_2"
    
    if [ "$TTL_RESULT_2" -gt 0 ] && [ "$TTL_RESULT_2" -le 300 ]; then
        echo "✅ TTL with EX working correctly!"
    elif [ "$TTL_RESULT_2" = "-2" ]; then
        echo "❌ TTL returning -2 for key with TTL!"
        echo "🐛 ISSUE: TTL method can't find key that was set with EX"
    else
        echo "❓ Unexpected TTL result for EX key: $TTL_RESULT_2"
    fi
else
    echo "❌ SET EX not working properly"
fi

echo ""
echo "🔍 DIAGNOSTIC TEST 3: Single core test (eliminate routing)"
echo "========================================================"

# Kill multi-core server and start single core
kill $SERVER_PID 2>/dev/null || true
sleep 3

echo "Starting single-core server to eliminate routing issues..."
./meteor_debug -h 127.0.0.1 -p 6379 -c 1 -s 1 -m 512 &
SINGLE_PID=$!
sleep 4

if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "✅ Single-core server responding"
    
    redis-cli -p 6379 flushall
    
    # Test with single core (no routing issues possible)
    redis-cli -p 6379 set single_test "single core value"
    GET_SINGLE=$(redis-cli -p 6379 get single_test)
    TTL_SINGLE=$(redis-cli -p 6379 ttl single_test)
    
    echo "Single core test:"
    echo "GET single_test -> '$GET_SINGLE'"
    echo "TTL single_test -> $TTL_SINGLE"
    
    if [ "$GET_SINGLE" = "single core value" ] && [ "$TTL_SINGLE" = "-1" ]; then
        echo "✅ Single core working perfectly!"
        echo "🐛 CONCLUSION: Multi-core routing was the issue"
    elif [ "$GET_SINGLE" = "single core value" ] && [ "$TTL_SINGLE" = "-2" ]; then
        echo "❌ Even single core gives -2!"
        echo "🐛 CONCLUSION: TTL method logic error, not routing"
    else
        echo "❌ Single core also has issues"
    fi
    
    kill $SINGLE_PID 2>/dev/null || true
else
    echo "❌ Single-core server not responding"
fi

echo ""
echo "🏆 DIAGNOSTIC SUMMARY"
echo "===================="
echo "Based on results above:"
echo "✅ If single-core works but multi-core fails → Routing issue"
echo "❌ If both single-core and multi-core fail → TTL method logic error"
echo "❓ If inconsistent results → Need deeper investigation"

EOF

echo "📋 Diagnostic commands created in /tmp/ttl_diagnostic_commands.txt"
echo ""
echo "🧪 Copy the commands from the file above and run on VM"













