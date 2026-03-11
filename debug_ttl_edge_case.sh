#!/bin/bash

echo "🔍 DEBUGGING TTL EDGE CASE ISSUE"
echo "Investigating why key without TTL returns -2 instead of -1"
echo ""

gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command "cd /mnt/externalDisk/meteor && 
    echo '🚀 Starting server for TTL debugging...' && 
    pkill -f meteor 2>/dev/null; sleep 2 && 
    ./meteor_commercial_lru_ttl_fixed -h 127.0.0.1 -p 6379 -c 4 -s 2 -m 512 &>/dev/null & 
    SERVER_PID=\$! && 
    sleep 3 && 
    echo 'Server PID:' \$SERVER_PID && 
    echo '' && 
    echo '🧪 TTL Edge Case Debug Tests:' && 
    echo '=============================' && 
    echo '' && 
    echo '1. Testing basic connectivity:' && 
    redis-cli -p 6379 ping && 
    echo '' && 
    echo '2. Setting a key without TTL:' && 
    redis-cli -p 6379 set debug_key 'no ttl value' && 
    echo 'SET result: Success' && 
    echo '' && 
    echo '3. Verifying key exists:' && 
    GET_RESULT=\$(redis-cli -p 6379 get debug_key) && 
    echo \"GET result: '\$GET_RESULT'\" && 
    echo '' && 
    echo '4. Checking TTL (should be -1):' && 
    TTL_RESULT=\$(redis-cli -p 6379 ttl debug_key) && 
    echo \"TTL result: \$TTL_RESULT\" && 
    if [ \"\$TTL_RESULT\" = \"-1\" ]; then 
      echo '✅ TTL correctly returns -1 for key without TTL'
    else 
      echo \"❌ TTL returned \$TTL_RESULT (expected -1)\"
      echo \"   This means either:\"
      echo \"   a) Key was not set properly\"
      echo \"   b) Key has TTL when it shouldn't\"
      echo \"   c) TTL logic has a bug\"
    fi && 
    echo '' && 
    echo '5. Testing SET with TTL for comparison:' && 
    redis-cli -p 6379 set ttl_key 'has ttl value' EX 60 && 
    TTL_WITH_TTL=\$(redis-cli -p 6379 ttl ttl_key) && 
    echo \"TTL for key with TTL: \$TTL_WITH_TTL (should be >0)\" && 
    echo '' && 
    echo '6. Testing non-existent key:' && 
    NONEXIST_TTL=\$(redis-cli -p 6379 ttl nonexistent_key_xyz) && 
    echo \"TTL for non-existent key: \$NONEXIST_TTL (should be -2)\" && 
    echo '' && 
    kill \$SERVER_PID 2>/dev/null && 
    echo '🔍 TTL Debug completed!'"













