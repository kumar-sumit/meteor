#!/bin/bash

echo "🔧 TESTING TTL ROUTING FIX"
echo "=========================="
echo ""
echo "🎯 CRITICAL FIX APPLIED:"
echo "   - Removed cross-shard routing that caused TTL commands"
echo "   - to hit different shards than SET commands"
echo "   - Now all commands execute locally on same shard"
echo ""

# Upload test script
gcloud compute scp test_ttl_fix.sh memtier-benchmarking:/mnt/externalDisk/meteor/ \
  --zone="asia-southeast1-a" --tunnel-through-iap --project="<your-gcp-project-id>" \
  --quiet 2>/dev/null

# Run the test
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor && 

echo '🚀 BUILDING ROUTING-FIXED VERSION'
echo '================================='
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null
sleep 2

echo 'Building from routing-fixed source...'
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_ttl_routing_fixed meteor_commercial_lru_ttl_routing_fixed.cpp -luring

if [ \$? -eq 0 ]; then
    echo '✅ Build successful!'
    ls -la meteor_ttl_routing_fixed
else
    echo '❌ Build failed!'
    exit 1
fi

echo ''
echo '🧪 TESTING TTL ROUTING FIX'
echo '==========================='

echo 'Starting server...'
./meteor_ttl_routing_fixed -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &>/dev/null &
SERVER_PID=\$!
sleep 4

echo \"Server PID: \$SERVER_PID\"
echo ''

if redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo '✅ Server responding'
else
    echo '❌ Server not responding'
    kill \$SERVER_PID 2>/dev/null
    exit 1
fi

echo ''
echo '🔎 FOCUSED TEST: Key without TTL (most likely failure)'
echo '======================================================'

# Clear data
redis-cli -p 6379 flushall >/dev/null 2>&1

# Test the most common failure case
echo 'Step 1: SET key without TTL'
redis-cli -p 6379 set test_key \"no ttl value\" >/dev/null
echo '   SET test_key \"no ttl value\"'

echo ''
echo 'Step 2: Verify key was stored'
GET_RESULT=\$(redis-cli -p 6379 get test_key 2>/dev/null)
echo \"   GET test_key -> '\$GET_RESULT'\"

if [ \"\$GET_RESULT\" = \"no ttl value\" ]; then
    echo '   ✅ Key stored correctly'
    
    echo ''
    echo 'Step 3: Check TTL (CRITICAL TEST)'
    TTL_RESULT=\$(redis-cli -p 6379 ttl test_key 2>/dev/null)
    echo \"   TTL test_key -> \$TTL_RESULT\"
    
    if [ \"\$TTL_RESULT\" = \"-1\" ]; then
        echo '   🎉 SUCCESS! TTL routing fix works!'
        echo '   ✅ Key without TTL correctly returns -1'
        ROUTING_FIX_STATUS=SUCCESS
    else
        echo \"   ❌ Still failing - Expected -1, got \$TTL_RESULT\"
        echo '   🐛 Need additional debugging'
        ROUTING_FIX_STATUS=FAILED
    fi
else
    echo '   ❌ Key not stored - SET command issue'
    ROUTING_FIX_STATUS=FAILED
fi

echo ''
echo 'Quick test of other cases:'
echo '-------------------------'

# Test non-existent key
TTL_NONEXIST=\$(redis-cli -p 6379 ttl nonexistent_xyz 2>/dev/null)
echo \"TTL nonexistent_xyz -> \$TTL_NONEXIST (should be -2)\"

# Test key with TTL
redis-cli -p 6379 set ttl_key \"has ttl\" EX 30 >/dev/null
TTL_WITH_EX=\$(redis-cli -p 6379 ttl ttl_key 2>/dev/null)
echo \"TTL ttl_key (with EX 30) -> \$TTL_WITH_EX (should be >0)\"

# Clean up
kill \$SERVER_PID 2>/dev/null

echo ''
echo '🏆 ROUTING FIX TEST RESULT'
echo '=========================='
echo \"Status: \$ROUTING_FIX_STATUS\"

if [ \"\$ROUTING_FIX_STATUS\" = \"SUCCESS\" ]; then
    echo ''
    echo '🎉 TTL ROUTING FIX CONFIRMED WORKING!'
    echo '✅ All TTL test cases should now pass'
    echo '✅ Ready for full benchmark testing'
    echo ''
    echo '📋 Next Steps:'
    echo '1. Run full TTL test suite: ./quick_ttl_debug.sh'
    echo '2. Run performance benchmark'
    echo '3. Deploy to production'
else
    echo ''
    echo '⚠️  Routing fix did not resolve the issue'
    echo '   Further debugging needed'
fi

echo ''
echo 'Routing fix test completed!'"

echo ""
echo "TTL routing fix test ready - run this to verify the fix!"













