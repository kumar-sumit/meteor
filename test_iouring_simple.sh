#!/bin/bash

# **SIMPLE io_uring TEST - Isolate the Connection Reset Issue**
echo "=== 🔍 SIMPLE io_uring CONNECTION TEST 🔍 ==="
echo "🎯 Testing individual operations to isolate 'Connection reset by peer'"
echo ""

# Test single core with detailed logging
echo "Starting io_uring server with single core..."
gcloud compute ssh memtier-benchmarking --zone "asia-southeast1-a" --project "<your-gcp-project-id>" --tunnel-through-iap --command "
cd /dev/shm

# Start server in background with timeout
timeout 20 bash -c 'METEOR_USE_IO_URING=1 ./meteor_advanced_iouring -h 127.0.0.1 -p 6390 -c 1' &
SERVER_PID=\$!

# Wait for server startup
sleep 3

echo '=== TESTING INDIVIDUAL OPERATIONS ==='

# Test 1: Simple PING
echo 'Test 1: PING'
if timeout 5 redis-cli -p 6390 ping 2>/dev/null | grep -q 'PONG'; then
    echo '✅ PING: SUCCESS'
else
    echo '❌ PING: FAILED'
fi

# Test 2: Single SET operation
echo 'Test 2: Single SET'
if timeout 5 redis-cli -p 6390 SET test_key test_value 2>/dev/null | grep -q 'OK'; then
    echo '✅ SET: SUCCESS'
else
    echo '❌ SET: FAILED'
fi

# Test 3: Single GET operation
echo 'Test 3: Single GET'
RESULT=\$(timeout 5 redis-cli -p 6390 GET test_key 2>/dev/null)
if [ \"\$RESULT\" = \"test_value\" ]; then
    echo '✅ GET: SUCCESS'
else
    echo \"❌ GET: FAILED (result: '\$RESULT')\"
fi

# Test 4: Multiple sequential operations
echo 'Test 4: Sequential operations'
SUCCESS_COUNT=0
for i in {1..5}; do
    if timeout 3 redis-cli -p 6390 SET key\$i value\$i 2>/dev/null | grep -q 'OK'; then
        SUCCESS_COUNT=\$((SUCCESS_COUNT + 1))
    fi
done
echo \"✅ Sequential SET: \$SUCCESS_COUNT/5 successful\"

# Test 5: Retrieve sequential operations
echo 'Test 5: Sequential GET operations'
SUCCESS_COUNT=0
for i in {1..5}; do
    RESULT=\$(timeout 3 redis-cli -p 6390 GET key\$i 2>/dev/null)
    if [ \"\$RESULT\" = \"value\$i\" ]; then
        SUCCESS_COUNT=\$((SUCCESS_COUNT + 1))
    fi
done
echo \"✅ Sequential GET: \$SUCCESS_COUNT/5 successful\"

# Test 6: Pipeline test (this is where we see 1M+ RPS)
echo 'Test 6: Small pipeline test'
if timeout 10 redis-cli -p 6390 --pipe 2>/dev/null <<< \$'SET pipe1 value1\\r\\nSET pipe2 value2\\r\\nGET pipe1\\r\\nGET pipe2\\r\\n' | grep -q 'value1'; then
    echo '✅ Pipeline: SUCCESS'
else
    echo '❌ Pipeline: FAILED'
fi

echo ''
echo '=== CONNECTION LIFECYCLE TEST ==='

# Test multiple connections
echo 'Testing connection handling...'
for i in {1..3}; do
    echo \"Connection \$i:\"
    timeout 3 redis-cli -p 6390 SET conn\$i test\$i 2>/dev/null && echo \"  SET: OK\" || echo \"  SET: FAILED\"
    timeout 3 redis-cli -p 6390 GET conn\$i 2>/dev/null && echo \"  GET: OK\" || echo \"  GET: FAILED\"
done

# Kill server
kill -9 \$SERVER_PID 2>/dev/null
wait \$SERVER_PID 2>/dev/null

echo ''
echo '🏁 Simple test completed'
"