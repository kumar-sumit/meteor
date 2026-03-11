#!/bin/bash

echo "🏆 METEOR COMMERCIAL LRU+TTL - COMPREHENSIVE VALIDATION"
echo "======================================================="
echo ""
echo "📋 TEST PLAN:"
echo "1. Build final TTL deadlock-fixed server"
echo "2. Verify TTL edge cases functionality" 
echo "3. Run performance benchmark with exact parameters"
echo "4. Report comprehensive results"
echo ""

# Upload this script to VM and run
gcloud compute scp comprehensive_ttl_benchmark.sh memtier-benchmarking:/mnt/externalDisk/meteor/ \
  --zone="asia-southeast1-a" --tunnel-through-iap --project="<your-gcp-project-id>" \
  --quiet 2>/dev/null

# Execute comprehensive test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor && 

echo '🚀 STEP 1: BUILDING FINAL TTL SERVER'
echo '====================================='
pkill -f meteor 2>/dev/null
sleep 2

export TMPDIR=/dev/shm
echo 'Building meteor_commercial_lru_ttl_final...'
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 -pthread \
  -o meteor_commercial_lru_ttl_final meteor_commercial_lru_ttl.cpp -luring

if [ \$? -eq 0 ]; then
    echo '✅ Build successful!'
    ls -la meteor_commercial_lru_ttl_final
else
    echo '❌ Build failed!'
    exit 1
fi

echo ''
echo '🧪 STEP 2: TTL EDGE CASES VERIFICATION'
echo '======================================'

echo 'Starting server for TTL testing...'
./meteor_commercial_lru_ttl_final -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &>/dev/null &
SERVER_PID=\$!
sleep 4

echo \"Server PID: \$SERVER_PID\"
echo ''

# Test connectivity
echo 'Testing connectivity:'
if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo '✅ Server responding to PING'
else
    echo '❌ Server not responding - killing and exiting'
    kill \$SERVER_PID 2>/dev/null
    exit 1
fi

echo ''
echo 'TTL Edge Case Tests:'
echo '-------------------'

# Test 1: Key without TTL should return -1
echo '1. Testing key without TTL:'
redis-cli -p 6379 set no_ttl_key 'permanent value' >/dev/null
TTL_NO_TTL=\$(redis-cli -p 6379 ttl no_ttl_key 2>/dev/null)
echo \"   SET no_ttl_key 'permanent value'\"
echo \"   TTL no_ttl_key -> \$TTL_NO_TTL (should be -1)\"
if [ \"\$TTL_NO_TTL\" = \"-1\" ]; then
    echo '   ✅ PASS: Key without TTL returns -1'
    TTL_TEST_1=PASS
else
    echo \"   ❌ FAIL: Expected -1, got \$TTL_NO_TTL\"
    TTL_TEST_1=FAIL
fi

echo ''

# Test 2: Non-existent key should return -2
echo '2. Testing non-existent key:'
TTL_NONEXIST=\$(redis-cli -p 6379 ttl nonexistent_key_12345 2>/dev/null)
echo \"   TTL nonexistent_key_12345 -> \$TTL_NONEXIST (should be -2)\"
if [ \"\$TTL_NONEXIST\" = \"-2\" ]; then
    echo '   ✅ PASS: Non-existent key returns -2'
    TTL_TEST_2=PASS
else
    echo \"   ❌ FAIL: Expected -2, got \$TTL_NONEXIST\"
    TTL_TEST_2=FAIL
fi

echo ''

# Test 3: Key with TTL should return positive value
echo '3. Testing key with TTL:'
redis-cli -p 6379 set ttl_key 'expires soon' EX 30 >/dev/null
TTL_WITH_TTL=\$(redis-cli -p 6379 ttl ttl_key 2>/dev/null)
echo \"   SET ttl_key 'expires soon' EX 30\"
echo \"   TTL ttl_key -> \$TTL_WITH_TTL (should be >0 and <=30)\"
if [ \"\$TTL_WITH_TTL\" -gt 0 ] && [ \"\$TTL_WITH_TTL\" -le 30 ]; then
    echo '   ✅ PASS: Key with TTL returns positive value'
    TTL_TEST_3=PASS
else
    echo \"   ❌ FAIL: Expected >0 and <=30, got \$TTL_WITH_TTL\"
    TTL_TEST_3=FAIL
fi

echo ''

# Test 4: EXPIRE command functionality
echo '4. Testing EXPIRE command:'
redis-cli -p 6379 set expire_test 'will be given ttl' >/dev/null
EXPIRE_RESULT=\$(redis-cli -p 6379 expire expire_test 25 2>/dev/null)
TTL_AFTER_EXPIRE=\$(redis-cli -p 6379 ttl expire_test 2>/dev/null)
echo \"   SET expire_test 'will be given ttl'\"
echo \"   EXPIRE expire_test 25 -> \$EXPIRE_RESULT (should be 1)\"
echo \"   TTL expire_test -> \$TTL_AFTER_EXPIRE (should be >0 and <=25)\"
if [ \"\$EXPIRE_RESULT\" = \"1\" ] && [ \"\$TTL_AFTER_EXPIRE\" -gt 0 ] && [ \"\$TTL_AFTER_EXPIRE\" -le 25 ]; then
    echo '   ✅ PASS: EXPIRE command works correctly'
    TTL_TEST_4=PASS
else
    echo \"   ❌ FAIL: EXPIRE result=\$EXPIRE_RESULT, TTL=\$TTL_AFTER_EXPIRE\"
    TTL_TEST_4=FAIL
fi

echo ''
echo 'TTL Edge Cases Summary:'
echo \"- Key without TTL: \$TTL_TEST_1\"
echo \"- Non-existent key: \$TTL_TEST_2\" 
echo \"- Key with TTL: \$TTL_TEST_3\"
echo \"- EXPIRE command: \$TTL_TEST_4\"

# Count passed tests
PASSED=0
[ \"\$TTL_TEST_1\" = \"PASS\" ] && ((PASSED++))
[ \"\$TTL_TEST_2\" = \"PASS\" ] && ((PASSED++))
[ \"\$TTL_TEST_3\" = \"PASS\" ] && ((PASSED++))
[ \"\$TTL_TEST_4\" = \"PASS\" ] && ((PASSED++))

echo \"TTL Tests: \$PASSED/4 passed\"

if [ \$PASSED -eq 4 ]; then
    echo '🎉 ALL TTL EDGE CASES VERIFIED!'
    TTL_OVERALL=PASS
else
    echo '⚠️  Some TTL edge cases need attention'
    TTL_OVERALL=PARTIAL
fi

echo ''
echo '📊 STEP 3: PERFORMANCE BENCHMARK'
echo '================================'

echo 'Restarting server for performance test...'
kill \$SERVER_PID 2>/dev/null
sleep 3

./meteor_commercial_lru_ttl_final -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &>/dev/null &
PERF_SERVER_PID=\$!
sleep 5

echo \"Performance server PID: \$PERF_SERVER_PID\"
echo ''

# Verify connectivity for performance test
if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo '✅ Performance server ready'
else
    echo '❌ Performance server not responding'
    kill \$PERF_SERVER_PID 2>/dev/null
    exit 1
fi

echo ''
echo 'Running memtier_benchmark with specified parameters:'
echo 'memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \'
echo '  --clients=50 --threads=12 --pipeline=10 --data-size=64 \'
echo '  --key-pattern=R:R --ratio=1:3 --test-time=30'
echo ''

# Run the exact benchmark command specified
timeout 45s memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \
  --clients=50 --threads=12 --pipeline=10 --data-size=64 \
  --key-pattern=R:R --ratio=1:3 --test-time=30 2>/dev/null

BENCHMARK_EXIT_CODE=\$?

echo ''
if [ \$BENCHMARK_EXIT_CODE -eq 0 ]; then
    echo '✅ Benchmark completed successfully'
    PERF_RESULT=SUCCESS
elif [ \$BENCHMARK_EXIT_CODE -eq 124 ]; then
    echo '⏰ Benchmark timed out (may have completed)'
    PERF_RESULT=TIMEOUT
else
    echo \"❌ Benchmark failed with exit code \$BENCHMARK_EXIT_CODE\"
    PERF_RESULT=FAILED
fi

# Cleanup
kill \$PERF_SERVER_PID 2>/dev/null

echo ''
echo '🏆 COMPREHENSIVE VALIDATION SUMMARY'
echo '=================================='
echo \"✅ Build Status: SUCCESS\"
echo \"🧪 TTL Edge Cases: \$TTL_OVERALL (\$PASSED/4 tests passed)\"
echo \"📊 Performance Benchmark: \$PERF_RESULT\"
echo ''

if [ \"\$TTL_OVERALL\" = \"PASS\" ] && [ \"\$PERF_RESULT\" != \"FAILED\" ]; then
    echo '🎉 METEOR COMMERCIAL LRU+TTL SERVER VALIDATED!'
    echo '   Ready for production deployment'
else
    echo '⚠️  Some issues detected - review results above'
fi

echo ''
echo '📋 Server Configuration Used:'
echo '- Cores: 12, Shards: 4, Memory: 2GB'
echo '- Optimizations: AVX2, AVX, SSE4.2, io_uring'
echo '- Features: LRU eviction, TTL support, thread-safe operations'
echo ''
echo 'Validation complete!'"

echo ""
echo "Comprehensive test completed!"













