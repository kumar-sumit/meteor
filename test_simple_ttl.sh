#!/bin/bash

echo "=========================================="
echo "🔧 TESTING SIMPLE TTL WORKING VERSION"
echo "$(date): Testing minimal TTL without hanging issues"
echo "=========================================="

# Test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== BUILDING SIMPLE TTL VERSION ==="
pkill -f meteor 2>/dev/null || true
sleep 3

# Use /dev/shm build
export TMPDIR=/dev/shm/build_tmp
mkdir -p /dev/shm/build_tmp
mkdir -p /dev/shm/meteor_build
cd /dev/shm/meteor_build
cp /mnt/externalDisk/meteor/meteor_simple_ttl_working.cpp .

g++ -std=c++20 -O3 -march=native -DNDEBUG -DBOOST_FIBER_NO_EXCEPTIONS -pthread \
    meteor_simple_ttl_working.cpp -o meteor_simple_ttl \
    -lboost_fiber -lboost_context -lboost_system -luring 2>&1

if [ $? -ne 0 ]; then
    echo "❌ BUILD FAILED"
    exit 1
fi

cp meteor_simple_ttl /mnt/externalDisk/meteor/
chmod +x /mnt/externalDisk/meteor/meteor_simple_ttl
cd /mnt/externalDisk/meteor
rm -rf /dev/shm/meteor_build /dev/shm/build_tmp

echo "✅ SIMPLE TTL BUILD SUCCESSFUL"

echo ""
echo "=== TESTING SIMPLE TTL VERSION ==="
nohup ./meteor_simple_ttl -c 4 -s 4 > simple_ttl.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER FAILED TO START"
    tail -10 simple_ttl.log
    exit 1
fi

echo "✅ Simple TTL server started (PID: $SERVER_PID)"

echo ""
echo "=== NO-HANG VERIFICATION ==="

echo "Testing all commands should work without hanging..."

echo -n "PING: "
PING_TEST=$(timeout 3s redis-cli -p 6379 PING 2>/dev/null)
if [ $? -eq 0 ] && [ "$PING_TEST" = "PONG" ]; then
    echo "✅ $PING_TEST"
    PING_OK=true
else
    echo "❌ TIMEOUT/FAILED"
    PING_OK=false
fi

echo -n "SET test_key test_value: "
SET_TEST=$(timeout 3s redis-cli -p 6379 SET test_key test_value 2>/dev/null)
if [ $? -eq 0 ] && [ "$SET_TEST" = "OK" ]; then
    echo "✅ $SET_TEST"
    SET_OK=true
else
    echo "❌ TIMEOUT/FAILED"
    SET_OK=false
fi

echo -n "GET test_key: "
GET_TEST=$(timeout 3s redis-cli -p 6379 GET test_key 2>/dev/null)
if [ $? -eq 0 ] && [ "$GET_TEST" = "test_value" ]; then
    echo "✅ $GET_TEST (NO HANGING!)"
    GET_OK=true
else
    echo "❌ TIMEOUT/FAILED: '$GET_TEST'"
    GET_OK=false
fi

echo -n "TTL test_key: "
TTL_TEST=$(timeout 3s redis-cli -p 6379 TTL test_key 2>/dev/null)
if [ $? -eq 0 ] && [ "$TTL_TEST" = "-1" ]; then
    echo "✅ $TTL_TEST (NO HANGING!)"
    TTL_OK=true
else
    echo "❌ TIMEOUT/FAILED: '$TTL_TEST'"
    TTL_OK=false
fi

echo -n "EXPIRE test_key 60: "
EXPIRE_TEST=$(timeout 3s redis-cli -p 6379 EXPIRE test_key 60 2>/dev/null)
if [ $? -eq 0 ] && [ "$EXPIRE_TEST" = "1" ]; then
    echo "✅ $EXPIRE_TEST (NO HANGING!)"
    EXPIRE_OK=true
else
    echo "❌ TIMEOUT/FAILED: '$EXPIRE_TEST'"
    EXPIRE_OK=false
fi

echo -n "DEL test_key: "
DEL_TEST=$(timeout 3s redis-cli -p 6379 DEL test_key 2>/dev/null)
if [ $? -eq 0 ] && [ "$DEL_TEST" = "1" ]; then
    echo "✅ $DEL_TEST (NO HANGING!)"
    DEL_OK=true
else
    echo "❌ TIMEOUT/FAILED: '$DEL_TEST'"
    DEL_OK=false
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 SIMPLE TTL RESULTS"
echo "=========================================="

WORKING_COMMANDS=0
TOTAL_COMMANDS=6

[ "$PING_OK" = true ] && echo "✅ PING: Working" && WORKING_COMMANDS=$((WORKING_COMMANDS + 1)) || echo "❌ PING: Failed"
[ "$SET_OK" = true ] && echo "✅ SET: Working" && WORKING_COMMANDS=$((WORKING_COMMANDS + 1)) || echo "❌ SET: Failed"
[ "$GET_OK" = true ] && echo "✅ GET: Working (No Hang!)" && WORKING_COMMANDS=$((WORKING_COMMANDS + 1)) || echo "❌ GET: Still hanging"
[ "$TTL_OK" = true ] && echo "✅ TTL: Working (No Hang!)" && WORKING_COMMANDS=$((WORKING_COMMANDS + 1)) || echo "❌ TTL: Still hanging"
[ "$EXPIRE_OK" = true ] && echo "✅ EXPIRE: Working (No Hang!)" && WORKING_COMMANDS=$((WORKING_COMMANDS + 1)) || echo "❌ EXPIRE: Still hanging"
[ "$DEL_OK" = true ] && echo "✅ DEL: Working (No Hang!)" && WORKING_COMMANDS=$((WORKING_COMMANDS + 1)) || echo "❌ DEL: Still hanging"

echo ""
echo "Success Rate: $WORKING_COMMANDS/$TOTAL_COMMANDS commands working"

if [ "$WORKING_COMMANDS" -eq "$TOTAL_COMMANDS" ]; then
    echo ""
    echo "🎉 COMPLETE SUCCESS! 🎉"
    echo "✅ ALL HANGING ISSUES RESOLVED!"
    echo "✅ Simple TTL implementation working perfectly!"
    echo "✅ Ready to enhance with full TTL functionality!"
elif [ "$WORKING_COMMANDS" -ge 4 ]; then
    echo ""
    echo "✅ EXCELLENT PROGRESS!"
    echo "Major hanging issues resolved!"
else
    echo ""
    echo "⚠️ STILL DEBUGGING NEEDED"
    echo "Core hanging issues persist"
fi

echo ""
echo "$(date): Simple TTL test complete!"

EOF












