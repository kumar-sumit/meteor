#!/bin/bash

echo "🔥 TESTING TTL DEADLOCK FIX"
echo "==========================="
echo ""
echo "🎯 CRITICAL FIXES APPLIED:"
echo "  ✅ Removed cross-shard routing bug"  
echo "  ✅ Fixed TTL method deadlock (moved expiry check inside lock)"
echo "  ✅ Fixed GET method deadlock (moved expiry check inside lock)"
echo "  ✅ Eliminated external lazy_expire_if_needed calls"
echo ""

# Upload and run test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor &&

echo '🚀 BUILDING DEADLOCK-FIXED VERSION'
echo '=================================='
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 2

echo 'Building from deadlock-fixed source...'
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_ttl_deadlock_fixed meteor_commercial_lru_ttl_deadlock_fixed.cpp -luring

if [ \$? -eq 0 ]; then
    echo '✅ Build successful!'
    ls -la meteor_ttl_deadlock_fixed
else
    echo '❌ Build failed!'
    exit 1
fi

echo ''
echo '🧪 TESTING DEADLOCK-FIXED VERSION'
echo '================================='

echo 'Starting server with deadlock fixes...'
timeout 60 ./meteor_ttl_deadlock_fixed -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &>/dev/null &
SERVER_PID=\$!
echo \"Server PID: \$SERVER_PID\"
sleep 4

# Test server connectivity
if timeout 5 redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo '✅ Server responding - no hanging!'
else
    echo '❌ Server not responding or hanging'
    kill \$SERVER_PID 2>/dev/null
    exit 1
fi

echo ''
echo '🎯 CRITICAL TEST: TTL without deadlock'
echo '======================================'

# Clear any existing data
redis-cli -p 6379 flushall >/dev/null 2>&1

echo 'Test 1: Set key without TTL'
redis-cli -p 6379 set critical_test \"no ttl here\" >/dev/null
RESULT1=\$(redis-cli -p 6379 get critical_test 2>/dev/null)
echo \"  SET critical_test -> GET result: '\$RESULT1'\"

if [ \"\$RESULT1\" = \"no ttl here\" ]; then
    echo '  ✅ Key stored successfully'
    
    echo ''
    echo 'Test 2: TTL check (CRITICAL - was returning -2, should be -1)'
    TTL_RESULT=\$(timeout 10 redis-cli -p 6379 ttl critical_test 2>/dev/null)
    EXIT_CODE=\$?
    
    if [ \$EXIT_CODE -eq 0 ]; then
        echo \"  TTL critical_test -> \$TTL_RESULT\"
        
        if [ \"\$TTL_RESULT\" = \"-1\" ]; then
            echo '  🎉 SUCCESS! TTL deadlock fix works!'
            echo '  ✅ Key without TTL correctly returns -1 (not -2)'
            DEADLOCK_FIX_STATUS=SUCCESS
        elif [ \"\$TTL_RESULT\" = \"-2\" ]; then
            echo '  ❌ Still failing - returning -2 instead of -1'
            echo '  🐛 Need further investigation'
            DEADLOCK_FIX_STATUS=PARTIAL
        else
            echo \"  ❓ Unexpected result: \$TTL_RESULT\"
            DEADLOCK_FIX_STATUS=UNEXPECTED
        fi
    else
        echo '  ❌ TTL command timed out - still hanging!'
        echo '  🚨 Deadlock not fully resolved'
        DEADLOCK_FIX_STATUS=HANGING
    fi
else
    echo '  ❌ Key not stored - SET command issue'
    DEADLOCK_FIX_STATUS=FAILED
fi

echo ''
echo 'Test 3: Quick validation of other cases'
echo '======================================='

# Test non-existent key (should be fast)
echo 'Testing non-existent key...'
TTL_NONEXIST=\$(timeout 5 redis-cli -p 6379 ttl nonexistent_key_abc 2>/dev/null)
echo \"  TTL nonexistent_key_abc -> \$TTL_NONEXIST (should be -2)\"

# Test key with TTL (should be fast)
echo 'Testing key with TTL...'
redis-cli -p 6379 set ttl_test \"expires soon\" EX 45 >/dev/null
TTL_WITH_EX=\$(timeout 5 redis-cli -p 6379 ttl ttl_test 2>/dev/null)
echo \"  TTL ttl_test (EX 45) -> \$TTL_WITH_EX (should be >0 and ≤45)\"

# Clean up
kill \$SERVER_PID 2>/dev/null || true

echo ''
echo '🏆 DEADLOCK FIX TEST RESULT'
echo '============================'
echo \"Status: \$DEADLOCK_FIX_STATUS\"

case \$DEADLOCK_FIX_STATUS in
    SUCCESS)
        echo ''
        echo '🎉 DEADLOCK FIX CONFIRMED WORKING!'
        echo '✅ No more hanging or timeouts'
        echo '✅ TTL returning correct values (-1 for no TTL)'
        echo '✅ Ready for full benchmark testing'
        ;;
    PARTIAL)
        echo ''
        echo '⚠️  Deadlock resolved but logic issue remains'
        echo '   TTL still returning -2 instead of -1'
        echo '   Need to check Entry constructor or has_ttl logic'
        ;;
    HANGING)
        echo ''
        echo '🚨 DEADLOCK STILL EXISTS'
        echo '   TTL command hanging/timing out'
        echo '   Need deeper deadlock analysis'
        ;;
    *)
        echo ''
        echo '⚠️  Unexpected result - need investigation'
        ;;
esac

echo ''
echo 'Next steps based on result:'
echo '1. If SUCCESS: Run full benchmark'
echo '2. If PARTIAL: Debug has_ttl logic'
echo '3. If HANGING: Analyze remaining deadlock'
echo ''

" 2>&1

echo ""
echo "🧪 TTL deadlock fix test completed!"













