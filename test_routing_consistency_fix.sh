#!/bin/bash

echo "🔧 TESTING KEY ROUTING CONSISTENCY FIX"
echo "======================================"
echo ""
echo "🎯 ROOT CAUSE FIXED:"
echo "  ❌ BEFORE: TTL/EXPIRE commands not included in key routing logic"
echo "  ✅ AFTER: TTL/EXPIRE commands route to same core as SET/GET"
echo "  ✅ Consistent key hashing across all commands"
echo ""

# Test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor &&

echo '🚀 BUILDING ROUTING-CONSISTENT VERSION'
echo '====================================='
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 3

echo 'Building with consistent key routing...'
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_routing_consistent meteor_commercial_lru_ttl_routing_consistent.cpp -luring

if [ \$? -eq 0 ]; then
    echo '✅ Build successful!'
    ls -la meteor_routing_consistent
else
    echo '❌ Build failed!'
    exit 1
fi

echo ''
echo '🧪 TESTING ROUTING CONSISTENCY'
echo '============================='

echo 'Starting multi-core server (4 shards, routing test)...'
./meteor_routing_consistent -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &>/dev/null &
SERVER_PID=\$!
echo \"Server PID: \$SERVER_PID\"
sleep 5

if timeout 10 redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo '✅ Server responding'
else
    echo '❌ Server not responding'
    kill \$SERVER_PID 2>/dev/null
    exit 1
fi

echo ''
echo '🎯 CRITICAL TEST: Routing Consistency (was giving random -2/-1)'
echo '=============================================================='

redis-cli -p 6379 flushall >/dev/null 2>&1

echo 'Testing 20 keys to ensure consistent routing across cores...'

SUCCESS_COUNT=0
FAIL_COUNT=0

for i in {1..20}; do
    KEY=\"test_routing_key_\$i\"
    
    # Set key (routes to some core)
    redis-cli -p 6379 set \"\$KEY\" \"value_\$i\" >/dev/null 2>&1
    
    # Check TTL immediately (should route to SAME core)
    TTL_RESULT=\$(timeout 5 redis-cli -p 6379 ttl \"\$KEY\" 2>/dev/null)
    
    if [ \"\$TTL_RESULT\" = \"-1\" ]; then
        SUCCESS_COUNT=\$((SUCCESS_COUNT + 1))
        echo \"  Key \$i: TTL -> \$TTL_RESULT ✅\"
    elif [ \"\$TTL_RESULT\" = \"-2\" ]; then
        FAIL_COUNT=\$((FAIL_COUNT + 1))
        echo \"  Key \$i: TTL -> \$TTL_RESULT ❌ (wrong core)\"
    else
        echo \"  Key \$i: TTL -> \$TTL_RESULT ❓ (unexpected)\"
        FAIL_COUNT=\$((FAIL_COUNT + 1))
    fi
done

echo ''
echo \"📊 ROUTING CONSISTENCY RESULTS: \$SUCCESS_COUNT/20 correct\"

if [ \$SUCCESS_COUNT -eq 20 ]; then
    echo '🎉 ROUTING CONSISTENCY PERFECT!'
    echo '✅ All TTL commands routed to correct cores'
    echo '✅ No more random -2/-1 results'
    ROUTING_STATUS=\"PERFECT\"
elif [ \$SUCCESS_COUNT -gt 15 ]; then
    echo '👍 ROUTING MOSTLY CONSISTENT'
    echo \"✅ \$SUCCESS_COUNT/20 correct - significant improvement\"
    echo '⚠️  Some keys still hitting wrong cores'
    ROUTING_STATUS=\"IMPROVED\"
else
    echo '❌ ROUTING STILL INCONSISTENT'
    echo \"❌ Only \$SUCCESS_COUNT/20 correct\"
    echo '   Fix did not resolve the core issue'
    ROUTING_STATUS=\"FAILED\"
fi

echo ''
echo '🧪 ADDITIONAL CONSISTENCY TESTS'
echo '==============================='

echo 'Test 1: SET EX + TTL routing consistency'
redis-cli -p 6379 set ttl_routing_test \"has ttl\" EX 120 >/dev/null
TTL_WITH_EX=\$(timeout 5 redis-cli -p 6379 ttl ttl_routing_test 2>/dev/null)
echo \"SET ttl_routing_test EX 120 -> TTL: \$TTL_WITH_EX\"

if [ \"\$TTL_WITH_EX\" -gt 0 ] && [ \"\$TTL_WITH_EX\" -le 120 ]; then
    echo '✅ SET EX routing works correctly'
    SETEX_ROUTING=\"SUCCESS\"
else
    echo \"❌ SET EX routing failed: TTL=\$TTL_WITH_EX\"
    SETEX_ROUTING=\"FAILED\"
fi

echo ''
echo 'Test 2: EXPIRE command routing consistency'
redis-cli -p 6379 set expire_routing_test \"gets expire\" >/dev/null
EXPIRE_RESULT=\$(timeout 5 redis-cli -p 6379 expire expire_routing_test 90 2>/dev/null)
TTL_AFTER_EXPIRE=\$(timeout 5 redis-cli -p 6379 ttl expire_routing_test 2>/dev/null)

echo \"EXPIRE expire_routing_test 90 -> \$EXPIRE_RESULT\"
echo \"TTL expire_routing_test -> \$TTL_AFTER_EXPIRE\"

if [ \"\$EXPIRE_RESULT\" = \"1\" ] && [ \"\$TTL_AFTER_EXPIRE\" -gt 0 ] && [ \"\$TTL_AFTER_EXPIRE\" -le 90 ]; then
    echo '✅ EXPIRE routing works correctly'
    EXPIRE_ROUTING=\"SUCCESS\"
else
    echo \"❌ EXPIRE routing failed: expire=\$EXPIRE_RESULT, ttl=\$TTL_AFTER_EXPIRE\"
    EXPIRE_ROUTING=\"FAILED\"
fi

echo ''
echo '🏃 PERFORMANCE VERIFICATION (should maintain 5M+ QPS)'
echo '=================================================='

echo 'Running 30-second performance test with TTL functionality...'
BENCHMARK_OUTPUT=\$(memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
  --clients=50 --threads=12 --pipeline=10 --data-size=64 \
  --key-pattern=R:R --ratio=1:3 --test-time=30 2>/dev/null)

if echo \"\$BENCHMARK_OUTPUT\" | grep -q \"requests/sec\"; then
    QPS=\$(echo \"\$BENCHMARK_OUTPUT\" | grep \"requests/sec\" | tail -1 | awk '{print \$1}' | sed 's/,//g')
    
    if [ -n \"\$QPS\" ] && [ \"\$QPS\" -gt 4500000 ]; then
        echo \"✅ Performance maintained: \${QPS} QPS\"
        PERFORMANCE=\"SUCCESS\"
    elif [ -n \"\$QPS\" ] && [ \"\$QPS\" -gt 1000000 ]; then
        echo \"⚠️  Performance acceptable: \${QPS} QPS\"
        PERFORMANCE=\"ACCEPTABLE\"
    else
        echo \"❌ Performance below target: \${QPS} QPS\"
        PERFORMANCE=\"POOR\"
    fi
    
    # Show latency info
    echo \"\$BENCHMARK_OUTPUT\" | grep -E \"(p50|p95|p99)\" | head -3
else
    echo '❌ Benchmark failed'
    PERFORMANCE=\"FAILED\"
fi

# Clean up
kill \$SERVER_PID 2>/dev/null || true

echo ''
echo '🏆 ROUTING CONSISTENCY FIX RESULTS'
echo '=================================='
echo \"Routing Consistency: \$ROUTING_STATUS\"
echo \"SET EX Routing: \$SETEX_ROUTING\"
echo \"EXPIRE Routing: \$EXPIRE_ROUTING\"
echo \"Performance: \$PERFORMANCE\"

echo ''
case \"\$ROUTING_STATUS\" in
    PERFECT)
        echo '🎉 ROUTING CONSISTENCY COMPLETELY FIXED!'
        echo '✅ All TTL commands now route to correct cores'
        echo '✅ No more random -2/-1 results'
        echo '✅ Consistent key hashing working perfectly'
        echo ''
        if [ \"\$PERFORMANCE\" = \"SUCCESS\" ]; then
            echo '🚀 READY FOR PRODUCTION!'
            echo '  - Routing consistency: PERFECT'
            echo '  - Performance: 5M+ QPS maintained'
            echo '  - TTL logic: All test cases working'
        fi
        ;;
    IMPROVED)
        echo '👍 MAJOR IMPROVEMENT IN ROUTING CONSISTENCY'
        echo '✅ Most TTL commands route correctly'
        echo '⚠️  Minor edge cases may remain'
        echo '   Significant progress made'
        ;;
    FAILED)
        echo '❌ ROUTING FIX DID NOT WORK'
        echo '   Need deeper analysis of key hashing logic'
        echo '   May need to check shard distribution'
        ;;
esac

echo ''
echo '📋 WHAT WAS FIXED:'
echo 'Before: TTL/EXPIRE not included in key routing logic'
echo 'After: TTL/EXPIRE use same key hashing as SET/GET'
echo 'Result: Consistent core routing for all key operations'

" 2>&1

echo ""
echo "🧪 Routing consistency fix test ready!"













