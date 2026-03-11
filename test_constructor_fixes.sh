#!/bin/bash

echo "🔧 TESTING CONSTRUCTOR FIXES"
echo "============================="
echo ""
echo "🎯 FIXES APPLIED:"
echo "  ✅ Fixed BatchOperation constructor mismatch (SET EX hanging)"
echo "  ✅ Fixed TTL detection in pipeline processing (-2 vs -1 issue)" 
echo "  ✅ Added proper TTL parameter handling"
echo ""

# Test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor &&

echo '🚀 BUILDING CONSTRUCTOR-FIXED VERSION'
echo '====================================='
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 2

echo 'Building from constructor-fixed source...'
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_constructor_fixed meteor_commercial_lru_ttl_constructor_fixed.cpp -luring

if [ \$? -eq 0 ]; then
    echo '✅ Build successful!'
else
    echo '❌ Build failed!'
    exit 1
fi

echo ''
echo '🧪 TESTING CONSTRUCTOR FIXES'
echo '============================='

echo 'Starting server with constructor fixes...'
timeout 60 ./meteor_constructor_fixed -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &>/dev/null &
SERVER_PID=\$!
echo \"Server PID: \$SERVER_PID\"
sleep 4

# Test basic connectivity (should not hang)
if timeout 10 redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo '✅ Server responding - no startup hanging!'
else
    echo '❌ Server not responding'
    kill \$SERVER_PID 2>/dev/null
    exit 1
fi

echo ''
echo '🎯 CRITICAL TEST 1: SET EX should not hang'
echo '==========================================='

echo 'Testing SET with EX (was hanging before)...'
START_TIME=\$(date +%s)
timeout 15 redis-cli -p 6379 set hang_test \"this had EX issues\" EX 60 >/dev/null
EXIT_CODE=\$?
END_TIME=\$(date +%s)
DURATION=\$((END_TIME - START_TIME))

echo \"SET EX execution time: \${DURATION} seconds\"

if [ \$EXIT_CODE -eq 0 ]; then
    echo '✅ SET EX completed successfully - no hanging!'
    SETEX_STATUS=\"SUCCESS\"
    
    # Verify key was stored
    GET_RESULT=\$(timeout 5 redis-cli -p 6379 get hang_test 2>/dev/null)
    echo \"GET hang_test -> '\$GET_RESULT'\"
    
    if [ \"\$GET_RESULT\" = \"this had EX issues\" ]; then
        echo '✅ Key stored correctly with SET EX'
    else
        echo '⚠️  Key not found - SET EX may not have worked properly'
        SETEX_STATUS=\"PARTIAL\"
    fi
else
    echo '❌ SET EX timed out or failed - still hanging!'
    SETEX_STATUS=\"HANGING\"
fi

echo ''
echo '🎯 CRITICAL TEST 2: TTL should return -1 (not -2)'
echo '================================================'

# Clear data first
redis-cli -p 6379 flushall >/dev/null 2>&1

echo 'Setting key without TTL...'
redis-cli -p 6379 set ttl_test \"no expiry\" >/dev/null

# Verify key exists
GET_CHECK=\$(redis-cli -p 6379 get ttl_test 2>/dev/null)
echo \"GET ttl_test -> '\$GET_CHECK'\"

if [ \"\$GET_CHECK\" = \"no expiry\" ]; then
    echo '✅ Key stored successfully'
    
    echo 'Testing TTL (critical - should be -1, not -2)...'
    TTL_RESULT=\$(timeout 10 redis-cli -p 6379 ttl ttl_test 2>/dev/null)
    EXIT_CODE=\$?
    
    if [ \$EXIT_CODE -eq 0 ]; then
        echo \"TTL ttl_test -> \$TTL_RESULT\"
        
        if [ \"\$TTL_RESULT\" = \"-1\" ]; then
            echo '🎉 SUCCESS! TTL correctly returns -1 for no TTL'
            TTL_STATUS=\"SUCCESS\"
        elif [ \"\$TTL_RESULT\" = \"-2\" ]; then
            echo '❌ Still failing - TTL returning -2 instead of -1'
            TTL_STATUS=\"STILL_FAILING\"
        else
            echo \"❓ Unexpected TTL result: \$TTL_RESULT\"
            TTL_STATUS=\"UNEXPECTED\"
        fi
    else
        echo '❌ TTL command timed out - still hanging!'
        TTL_STATUS=\"HANGING\"
    fi
else
    echo '❌ Key not stored - SET command failing'
    TTL_STATUS=\"SET_FAILED\"
fi

echo ''
echo '🧪 QUICK TEST 3: SET EX with TTL check'
echo '======================================'

echo 'Testing SET EX combined with TTL...'
redis-cli -p 6379 set combo_test \"expires\" EX 45 >/dev/null
COMBO_TTL=\$(timeout 5 redis-cli -p 6379 ttl combo_test 2>/dev/null)
echo \"SET combo_test EX 45 -> TTL: \$COMBO_TTL (should be >0 and ≤45)\"

if [ \"\$COMBO_TTL\" -gt 0 ] && [ \"\$COMBO_TTL\" -le 45 ]; then
    echo '✅ SET EX + TTL working correctly'
    COMBO_STATUS=\"SUCCESS\"
else
    echo \"❌ SET EX + TTL failed - TTL: \$COMBO_TTL\"
    COMBO_STATUS=\"FAILED\"
fi

# Clean up
kill \$SERVER_PID 2>/dev/null || true

echo ''
echo '🏆 CONSTRUCTOR FIXES TEST RESULTS'
echo '================================='
echo \"SET EX Status: \$SETEX_STATUS\"
echo \"TTL Status: \$TTL_STATUS\"
echo \"SET EX + TTL Status: \$COMBO_STATUS\"

echo ''
case \"\$SETEX_STATUS-\$TTL_STATUS\" in
    SUCCESS-SUCCESS)
        echo '🎉 ALL CONSTRUCTOR FIXES WORKING!'
        echo '✅ SET EX no longer hangs'
        echo '✅ TTL correctly returns -1 for keys without TTL'
        echo '✅ Ready for full benchmark testing'
        ;;
    SUCCESS-STILL_FAILING)
        echo '⚠️  SET EX fixed but TTL logic still has issues'
        echo '   Constructor fix worked for hanging'
        echo '   Need to debug Entry has_ttl logic further'
        ;;
    HANGING-*)
        echo '🚨 SET EX still hanging - constructor fix incomplete'
        echo '   Need deeper analysis of batch processing'
        ;;
    SUCCESS-HANGING)
        echo '⚠️  SET EX works but TTL still hangs'
        echo '   Partial constructor fix - TTL method still has deadlock'
        ;;
    *)
        echo '❓ Mixed results - need case-by-case analysis'
        ;;
esac

echo ''
echo 'Expected final state:'
echo '✅ SET EX completes in <5 seconds'
echo '✅ TTL returns -1 for keys without TTL'
echo '✅ TTL returns >0 for keys with TTL'
echo '✅ No hanging or timeouts'

" 2>&1

echo ""
echo "🧪 Constructor fixes test ready!"













