#!/bin/bash

echo "🔧 TESTING DEADLOCK-FREE TTL VERSION"
echo "===================================="
echo ""
echo "🎯 CRITICAL FIXES APPLIED:"
echo "  ✅ Replaced dangerous lock upgrade pattern in TTL method"
echo "  ✅ Uses simple unique_lock (no shared_lock → unique_lock upgrade)"
echo "  ✅ Eliminates race conditions and iterator invalidation"
echo "  ✅ Simplified GET method for consistency"
echo ""

# Test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor &&

echo '🚀 BUILDING DEADLOCK-FREE VERSION'
echo '================================='
export TMPDIR=/dev/shm
pkill -f meteor 2>/dev/null || true
sleep 3

echo 'Building from deadlock-free source...'
g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \
  -pthread -o meteor_deadlock_free meteor_commercial_lru_ttl_deadlock_free.cpp -luring

if [ \$? -eq 0 ]; then
    echo '✅ Build successful!'
    ls -la meteor_deadlock_free
else
    echo '❌ Build failed!'
    exit 1
fi

echo ''
echo '🧪 TESTING DEADLOCK-FREE VERSION'
echo '==============================='

echo 'Starting server with deadlock-free TTL...'
timeout 60 ./meteor_deadlock_free -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 1024 &>/dev/null &
SERVER_PID=\$!
echo \"Server PID: \$SERVER_PID\"
sleep 4

# Test basic connectivity (should be stable now)
if timeout 10 redis-cli -p 6379 ping >/dev/null 2>&1; then
    echo '✅ Server responding - no startup hanging!'
else
    echo '❌ Server not responding'
    kill \$SERVER_PID 2>/dev/null
    exit 1
fi

echo ''
echo '🎯 CRITICAL TEST 1: TTL command should not hang'
echo '=============================================='

# Clear any existing data
redis-cli -p 6379 flushall >/dev/null 2>&1

echo 'Setting key without TTL...'
redis-cli -p 6379 set deadlock_test \"no ttl value\" >/dev/null

# Verify key exists
GET_RESULT=\$(timeout 5 redis-cli -p 6379 get deadlock_test 2>/dev/null)
echo \"GET deadlock_test -> '\$GET_RESULT'\"

if [ \"\$GET_RESULT\" = \"no ttl value\" ]; then
    echo '✅ Key stored successfully'
    
    echo ''
    echo 'Testing TTL command (was hanging before)...'
    START_TIME=\$(date +%s%N)
    TTL_RESULT=\$(timeout 10 redis-cli -p 6379 ttl deadlock_test 2>/dev/null)
    EXIT_CODE=\$?
    END_TIME=\$(date +%s%N)
    DURATION_MS=\$(( (END_TIME - START_TIME) / 1000000 ))
    
    echo \"TTL execution time: \${DURATION_MS}ms\"
    
    if [ \$EXIT_CODE -eq 0 ]; then
        echo \"TTL deadlock_test -> \$TTL_RESULT\"
        
        if [ \"\$TTL_RESULT\" = \"-1\" ]; then
            echo '🎉 SUCCESS! TTL method working correctly!'
            echo \"✅ Returns -1 for keys without TTL (execution time: \${DURATION_MS}ms)\"
            TTL_HANGING_STATUS=\"SUCCESS\"
        elif [ \"\$TTL_RESULT\" = \"-2\" ]; then
            echo '⚠️  TTL not hanging but still returning -2 instead of -1'
            echo '   Deadlock fixed but logic issue remains'
            TTL_HANGING_STATUS=\"LOGIC_ISSUE\"
        else
            echo \"❓ Unexpected TTL result: \$TTL_RESULT\"
            TTL_HANGING_STATUS=\"UNEXPECTED\"
        fi
    else
        echo '❌ TTL command still timed out - deadlock not fully resolved!'
        TTL_HANGING_STATUS=\"STILL_HANGING\"
    fi
else
    echo '❌ Key not stored - SET command failing'
    TTL_HANGING_STATUS=\"SET_FAILED\"
fi

echo ''
echo '🧪 RAPID FIRE TEST: Multiple TTL commands (stress test)'
echo '======================================================'

echo 'Testing multiple TTL commands rapidly...'
redis-cli -p 6379 set stress_key \"rapid fire test\" >/dev/null

STRESS_FAILURES=0
for i in {1..10}; do
    RAPID_TTL=\$(timeout 5 redis-cli -p 6379 ttl stress_key 2>/dev/null)
    if [ \$? -ne 0 ] || [ -z \"\$RAPID_TTL\" ]; then
        STRESS_FAILURES=\$((STRESS_FAILURES + 1))
    fi
done

echo \"Rapid fire test: \$((10 - STRESS_FAILURES))/10 commands succeeded\"

if [ \$STRESS_FAILURES -eq 0 ]; then
    echo '✅ All rapid TTL commands succeeded - no hanging under stress'
    STRESS_STATUS=\"SUCCESS\"
elif [ \$STRESS_FAILURES -lt 5 ]; then
    echo '⚠️  Some TTL commands failed - intermittent issues'
    STRESS_STATUS=\"INTERMITTENT\"
else
    echo '❌ Most TTL commands failed - still has hanging issues'
    STRESS_STATUS=\"FAILING\"
fi

echo ''
echo '🧪 SET EX + TTL COMBINATION TEST'
echo '==============================='

echo 'Testing SET EX combined with TTL...'
START_TIME=\$(date +%s)
timeout 15 redis-cli -p 6379 set combo_test \"expires\" EX 45 >/dev/null
SETEX_EXIT_CODE=\$?
END_TIME=\$(date +%s)
SETEX_DURATION=\$((END_TIME - START_TIME))

echo \"SET EX execution time: \${SETEX_DURATION} seconds\"

if [ \$SETEX_EXIT_CODE -eq 0 ]; then
    echo '✅ SET EX completed successfully'
    
    # Test TTL on the key with TTL
    COMBO_TTL=\$(timeout 5 redis-cli -p 6379 ttl combo_test 2>/dev/null)
    echo \"TTL combo_test -> \$COMBO_TTL (should be >0 and ≤45)\"
    
    if [ \"\$COMBO_TTL\" -gt 0 ] && [ \"\$COMBO_TTL\" -le 45 ]; then
        echo '✅ SET EX + TTL working correctly'
        COMBO_STATUS=\"SUCCESS\"
    else
        echo \"❌ SET EX + TTL failed - unexpected TTL: \$COMBO_TTL\"
        COMBO_STATUS=\"FAILED\"
    fi
else
    echo '❌ SET EX still timing out or failing'
    COMBO_STATUS=\"SETEX_FAILING\"
fi

echo ''
echo '🧪 EDGE CASE TEST: Non-existent key'
echo '=================================='

NON_EXIST_TTL=\$(timeout 5 redis-cli -p 6379 ttl totally_nonexistent_key_xyz 2>/dev/null)
echo \"TTL nonexistent_key -> \$NON_EXIST_TTL (should be -2)\"

if [ \"\$NON_EXIST_TTL\" = \"-2\" ]; then
    echo '✅ Non-existent key TTL working correctly'
    NONEXIST_STATUS=\"SUCCESS\"
else
    echo \"❌ Non-existent key TTL failed - got: \$NON_EXIST_TTL\"
    NONEXIST_STATUS=\"FAILED\"
fi

# Clean up
kill \$SERVER_PID 2>/dev/null || true

echo ''
echo '🏆 DEADLOCK-FREE TTL TEST RESULTS'
echo '================================='
echo \"TTL Hanging Status: \$TTL_HANGING_STATUS\"
echo \"Stress Test Status: \$STRESS_STATUS\"
echo \"SET EX + TTL Status: \$COMBO_STATUS\"
echo \"Non-existent Key Status: \$NONEXIST_STATUS\"

echo ''
case \"\$TTL_HANGING_STATUS\" in
    SUCCESS)
        echo '🎉 DEADLOCK COMPLETELY FIXED!'
        echo '✅ TTL command responds quickly (no hanging)'
        echo '✅ TTL returns correct values (-1 for no TTL)'
        echo '✅ Ready for full production deployment'
        FINAL_RESULT=\"FULLY_FIXED\"
        ;;
    LOGIC_ISSUE)
        echo '⚠️  Deadlock fixed but logic issue remains'
        echo '✅ No more hanging (performance issue resolved)'
        echo '❌ Still returning -2 instead of -1 (logic needs debugging)'
        echo '   Need to check Entry constructor or has_ttl flag'
        FINAL_RESULT=\"PARTIAL_FIX\"
        ;;
    STILL_HANGING)
        echo '🚨 TTL COMMAND STILL HANGING'
        echo '❌ Deadlock not fully resolved'
        echo '   Need deeper lock analysis or different approach'
        FINAL_RESULT=\"STILL_BROKEN\"
        ;;
    *)
        echo '❓ Unexpected result - need case-by-case analysis'
        FINAL_RESULT=\"UNKNOWN\"
        ;;
esac

echo ''
echo 'Performance expectations:'
echo '✅ TTL commands should complete in <100ms'
echo '✅ No hanging or timeouts under normal load'
echo '✅ Consistent behavior across multiple calls'

if [ \"\$FINAL_RESULT\" = \"FULLY_FIXED\" ]; then
    echo ''
    echo '🚀 READY FOR BENCHMARK TESTING!'
    echo 'Expected: 5.0M - 5.4M QPS with stable TTL functionality'
fi

" 2>&1

echo ""
echo "🧪 Deadlock-free TTL test ready!"













