#!/bin/bash

echo "🔍 TESTING BASE PHASE 1.2B KEY ROUTING ISSUE"
echo "============================================="
echo ""
echo "Testing if base Phase 1.2B has GET fails after SET due to routing"
echo ""

cat > /tmp/vm_base_routing_test.txt << 'EOF'
# ===== SSH TO VM =====
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>"

# ===== TEST BASE PHASE 1.2B ROUTING =====
cd /mnt/externalDisk/meteor
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 3

echo "🧪 TESTING BASE PHASE 1.2B SYSCALL VERSION"
echo "=========================================="

# Build base Phase 1.2B
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 -pthread -o meteor_base_1_2b meteor_phase1_2b_syscall_reduction.cpp -luring

# ===== TEST 1: MULTI-CORE WITH DIFFERENT SHARDS =====
echo ""
echo "🔍 TEST 1: Multi-core (12C:4S) - Different cores, different shards"
echo "=================================================================="

./meteor_base_1_2b -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &
SERVER_PID_1=$!
sleep 5

if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "✅ Server responding on 12C:4S"
    
    redis-cli -p 6379 flushall
    
    # Test key routing consistency
    for i in {1..10}; do
        KEY="routing_test_$i"
        
        redis-cli -p 6379 set $KEY "value_$i" >/dev/null
        GET_RESULT=$(redis-cli -p 6379 get $KEY)
        
        if [ "$GET_RESULT" = "value_$i" ]; then
            echo "✅ Key $KEY: SET and GET consistent"
        else
            echo "❌ Key $KEY: SET worked but GET failed (routing issue!)"
            echo "   SET stored in one shard, GET checked different shard"
            break
        fi
    done
else
    echo "❌ 12C:4S server not responding"
fi

kill $SERVER_PID_1 2>/dev/null || true
sleep 3

# ===== TEST 2: CORES = SHARDS (Perfect 1:1 mapping) =====
echo ""
echo "🔍 TEST 2: Cores = Shards (12C:12S) - Perfect 1:1 mapping"
echo "=========================================================="

./meteor_base_1_2b -h 127.0.0.1 -p 6379 -c 12 -s 12 -m 2048 &
SERVER_PID_2=$!
sleep 5

if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "✅ Server responding on 12C:12S"
    
    redis-cli -p 6379 flushall
    
    # Test key routing with 1:1 core:shard mapping
    ROUTING_ISSUES=0
    for i in {1..10}; do
        KEY="perfect_routing_$i"
        
        redis-cli -p 6379 set $KEY "perfect_value_$i" >/dev/null
        GET_RESULT=$(redis-cli -p 6379 get $KEY)
        
        if [ "$GET_RESULT" = "perfect_value_$i" ]; then
            echo "✅ Key $KEY: SET and GET consistent (perfect routing)"
        else
            echo "❌ Key $KEY: SET worked but GET failed even with 1:1 mapping!"
            ROUTING_ISSUES=1
            break
        fi
    done
    
    if [ $ROUTING_ISSUES -eq 0 ]; then
        echo "🎉 12C:12S WORKS! Cores=Shards fixes routing issue"
    fi
else
    echo "❌ 12C:12S server not responding"
fi

kill $SERVER_PID_2 2>/dev/null || true
sleep 3

# ===== TEST 3: SINGLE CORE (Eliminate routing completely) =====
echo ""
echo "🔍 TEST 3: Single Core (1C:1S) - No routing needed"
echo "=================================================="

./meteor_base_1_2b -h 127.0.0.1 -p 6379 -c 1 -s 1 -m 512 &
SERVER_PID_3=$!
sleep 4

if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "✅ Server responding on 1C:1S"
    
    redis-cli -p 6379 flushall
    
    # Test with no routing (single core)
    redis-cli -p 6379 set single_routing_test "single_value"
    SINGLE_GET=$(redis-cli -p 6379 get single_routing_test)
    
    echo "Single core test:"
    echo "GET -> '$SINGLE_GET'"
    
    if [ "$SINGLE_GET" = "single_value" ]; then
        echo "✅ Single core works perfectly - confirms routing issue in multi-core"
    else
        echo "❌ Even single core fails - deeper issue than routing"
    fi
else
    echo "❌ 1C:1S server not responding"
fi

kill $SERVER_PID_3 2>/dev/null || true

# ===== TEST 4: BENCHMARK WITH FIXED ROUTING =====
echo ""
echo "🔍 TEST 4: Quick benchmark with perfect routing (12C:12S)"
echo "========================================================="

./meteor_base_1_2b -h 127.0.0.1 -p 6379 -c 12 -s 12 -m 2048 &
SERVER_PID_4=$!
sleep 5

if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo "✅ Running quick benchmark with perfect routing..."
    
    # Quick 15-second benchmark
    memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis --clients=20 --threads=8 --pipeline=10 --data-size=64 --key-pattern=R:R --ratio=1:3 --test-time=15
    
    echo ""
    echo "🎯 If benchmark shows high QPS with 12C:12S, routing issue confirmed and fixed"
else
    echo "❌ Perfect routing server not responding"
fi

kill $SERVER_PID_4 2>/dev/null || true

echo ""
echo "🏆 DIAGNOSTIC SUMMARY FOR BASE 1.2B"
echo "===================================="
echo ""
echo "EXPECTED RESULTS:"
echo "✅ 12C:4S → GET fails after SET (routing broken)"  
echo "✅ 12C:12S → GET works after SET (routing fixed)"
echo "✅ 1C:1S → GET works after SET (no routing needed)"
echo ""
echo "If this pattern holds, then:"
echo "→ Issue is cores > shards causing cross-core shard access"
echo "→ Solution is cores = shards OR proper cross-core access"

EOF

echo "📋 VM Base 1.2B routing test commands created"
echo ""
echo "🚀 COPY THESE COMMANDS TO VM:"
cat /tmp/vm_base_routing_test.txt













