#!/bin/bash

# **DEBUG io_uring CONNECTIVITY ISSUE**
echo "=== 🔍 DEBUG io_uring CONNECTIVITY 🔍 ==="
echo "🎯 Testing basic io_uring connectivity with single core"
echo ""

# Single core test to isolate issues
echo "Building fixed version..."
if ! gcloud compute ssh memtier-benchmarking --zone "asia-southeast1-a" --project "<your-gcp-project-id>" --tunnel-through-iap --command "cd /dev/shm && export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH && ./build_advanced_iouring.sh" > /dev/null 2>&1; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful"
echo ""

# Test single core io_uring
echo "=== TESTING SINGLE CORE io_uring ==="
echo "Starting server with detailed logging..."

gcloud compute ssh memtier-benchmarking --zone "asia-southeast1-a" --project "<your-gcp-project-id>" --tunnel-through-iap --command "
cd /dev/shm
timeout 15 bash -c 'METEOR_USE_IO_URING=1 ./meteor_advanced_iouring -h 127.0.0.1 -p 6390 -c 1' &
SERVER_PID=\$!

# Wait for server startup
sleep 3

echo 'Testing PING...'
if redis-cli -p 6390 ping > /dev/null 2>&1; then
    echo '✅ PING successful'
    
    echo 'Testing SET/GET...'
    redis-cli -p 6390 SET test_key test_value > /dev/null 2>&1
    RESULT=\$(redis-cli -p 6390 GET test_key 2>/dev/null)
    if [ \"\$RESULT\" = \"test_value\" ]; then
        echo '✅ SET/GET successful'
        echo '🎉 io_uring connectivity WORKING!'
    else
        echo '❌ SET/GET failed'
    fi
else
    echo '❌ PING failed - server not responding'
fi

# Kill server
kill -9 \$SERVER_PID 2>/dev/null
wait \$SERVER_PID 2>/dev/null
"

echo ""
echo "🏁 Debug test completed"