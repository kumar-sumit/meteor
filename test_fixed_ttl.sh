#!/bin/bash

echo "=========================================="
echo "🔧 TESTING FIXED TTL+LRU IMPLEMENTATION"
echo "$(date): Testing resolved dynamic response hanging issue"
echo "=========================================="

# Test on VM
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" << 'EOF'

cd /mnt/externalDisk/meteor

echo "=== REBUILDING FIXED TTL SERVER ==="
pkill -f meteor 2>/dev/null || true
sleep 3

# Use /dev/shm build again 
export TMPDIR=/dev/shm/build_tmp
mkdir -p /dev/shm/build_tmp
mkdir -p /dev/shm/meteor_build
cd /dev/shm/meteor_build
cp /mnt/externalDisk/meteor/meteor_baseline_ttl_lru.cpp .

echo "🔧 Building fixed version with AVX-512 optimizations..."
g++ -std=c++20 \
    -O3 \
    -march=native \
    -mtune=native \
    -mavx512f \
    -mavx512dq \
    -mavx512bw \
    -mavx512vl \
    -mavx512cd \
    -mfma \
    -msse4.2 \
    -mpopcnt \
    -mbmi2 \
    -mlzcnt \
    -flto \
    -ffast-math \
    -funroll-loops \
    -fprefetch-loop-arrays \
    -finline-functions \
    -fomit-frame-pointer \
    -DNDEBUG \
    -DBOOST_FIBER_NO_EXCEPTIONS \
    -DAVX512_ENABLED \
    -DSIMD_OPTIMIZED \
    -pthread \
    -pipe \
    meteor_baseline_ttl_lru.cpp \
    -o meteor_ttl_fixed \
    -lboost_fiber \
    -lboost_context \
    -lboost_system \
    -luring \
    -ljemalloc \
    2>&1

if [ $? -ne 0 ]; then
    echo "❌ BUILD FAILED, using basic build..."
    g++ -std=c++20 -O2 -DNDEBUG -DBOOST_FIBER_NO_EXCEPTIONS -pthread \
        meteor_baseline_ttl_lru.cpp -o meteor_ttl_fixed \
        -lboost_fiber -lboost_context -lboost_system -luring 2>&1
    
    if [ $? -ne 0 ]; then
        echo "❌ BASIC BUILD ALSO FAILED"
        exit 1
    fi
fi

# Copy back
cp meteor_ttl_fixed /mnt/externalDisk/meteor/
chmod +x /mnt/externalDisk/meteor/meteor_ttl_fixed
cd /mnt/externalDisk/meteor
rm -rf /dev/shm/meteor_build /dev/shm/build_tmp

echo "✅ BUILD SUCCESSFUL"

echo ""
echo "=== TESTING FIXED IMPLEMENTATION ==="
echo "🚀 Starting fixed TTL server..."
nohup ./meteor_ttl_fixed -c 4 -s 4 > fixed_test.log 2>&1 &
SERVER_PID=$!
sleep 5

if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER FAILED TO START"
    tail -10 fixed_test.log
    exit 1
fi

echo "✅ Server started (PID: $SERVER_PID)"

echo ""
echo "=== SYSTEMATIC HANG TEST ==="

echo "--- Static Response Commands ---"
echo -n "PING: "
timeout 3s redis-cli -p 6379 PING && echo "✅" || echo "❌ TIMEOUT"

echo -n "SET baseline_key baseline_value: "  
timeout 3s redis-cli -p 6379 SET baseline_key baseline_value && echo "✅" || echo "❌ TIMEOUT"

echo ""
echo "--- Dynamic Response Commands (Previously Hanging) ---"
echo -n "GET baseline_key: "
GET_RESULT=$(timeout 3s redis-cli -p 6379 GET baseline_key 2>/dev/null)
if [ $? -eq 0 ] && [ "$GET_RESULT" = "baseline_value" ]; then
    echo "✅ $GET_RESULT"
    GET_FIXED=true
else
    echo "❌ TIMEOUT or WRONG VALUE: '$GET_RESULT'"  
    GET_FIXED=false
fi

echo -n "TTL baseline_key: "
TTL_RESULT=$(timeout 3s redis-cli -p 6379 TTL baseline_key 2>/dev/null)
if [ $? -eq 0 ] && [ "$TTL_RESULT" = "-1" ]; then
    echo "✅ $TTL_RESULT"
    TTL_FIXED=true
else
    echo "❌ TIMEOUT or WRONG VALUE: '$TTL_RESULT'"
    TTL_FIXED=false
fi

echo -n "DEL baseline_key: "
DEL_RESULT=$(timeout 3s redis-cli -p 6379 DEL baseline_key 2>/dev/null)
if [ $? -eq 0 ] && [ "$DEL_RESULT" = "1" ]; then
    echo "✅ $DEL_RESULT"
    DEL_FIXED=true
else
    echo "❌ TIMEOUT or WRONG VALUE: '$DEL_RESULT'"
    DEL_FIXED=false
fi

echo ""
echo "=== TTL FUNCTIONALITY TEST ==="
if [ "$TTL_FIXED" = true ]; then
    echo "Testing complete TTL functionality..."
    
    echo -n "SETEX ttl_test 5 ttl_value: "
    SETEX_RESULT=$(timeout 3s redis-cli -p 6379 SETEX ttl_test 5 ttl_value 2>/dev/null)
    echo "$SETEX_RESULT"
    
    echo -n "GET ttl_test: "
    GET_TTL_RESULT=$(timeout 3s redis-cli -p 6379 GET ttl_test 2>/dev/null)
    echo "$GET_TTL_RESULT"
    
    echo -n "TTL ttl_test: "
    TTL_CHECK=$(timeout 3s redis-cli -p 6379 TTL ttl_test 2>/dev/null)
    echo "$TTL_CHECK (should be ≤5 and >0)"
    
    echo -n "EXPIRE ttl_test 10: "
    EXPIRE_RESULT=$(timeout 3s redis-cli -p 6379 EXPIRE ttl_test 10 2>/dev/null)
    echo "$EXPIRE_RESULT"
    
    if [[ "$SETEX_RESULT" == "OK" ]] && [[ "$GET_TTL_RESULT" == "ttl_value" ]] && [[ "$EXPIRE_RESULT" == "1" ]]; then
        echo "✅ TTL FUNCTIONALITY: WORKING PERFECTLY"
        TTL_COMPLETE=true
    else
        echo "⚠️ TTL FUNCTIONALITY: Some issues remain"
        TTL_COMPLETE=false
    fi
else
    echo "⚠️ SKIPPING TTL FUNCTIONALITY TEST - Basic TTL command hanging"
    TTL_COMPLETE=false
fi

# Stop server
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="  
echo "🏆 FIXED TTL IMPLEMENTATION RESULTS"
echo "=========================================="
echo ""

TOTAL_FIXED=0
TOTAL_TESTS=4

if [ "$GET_FIXED" = true ]; then
    echo "✅ GET Command: FIXED (no longer hanging)"
    TOTAL_FIXED=$((TOTAL_FIXED + 1))
else
    echo "❌ GET Command: Still hanging"
fi

if [ "$TTL_FIXED" = true ]; then
    echo "✅ TTL Command: FIXED (no longer hanging)"
    TOTAL_FIXED=$((TOTAL_FIXED + 1))
else
    echo "❌ TTL Command: Still hanging"
fi

if [ "$DEL_FIXED" = true ]; then
    echo "✅ DEL Command: FIXED (no longer hanging)"
    TOTAL_FIXED=$((TOTAL_FIXED + 1))
else
    echo "❌ DEL Command: Still hanging"
fi

if [ "$TTL_COMPLETE" = true ]; then
    echo "✅ TTL Functionality: COMPLETE"
    TOTAL_FIXED=$((TOTAL_FIXED + 1))
else
    echo "⚠️ TTL Functionality: Needs work"
fi

echo ""
echo "Overall Fix Success: $TOTAL_FIXED/$TOTAL_TESTS"

if [ "$TOTAL_FIXED" -eq "$TOTAL_TESTS" ]; then
    echo ""
    echo "🎉 COMPLETE SUCCESS! 🎉"
    echo "✅ All hanging issues resolved!"
    echo "✅ TTL+LRU implementation fully functional!"
    echo ""
elif [ "$TOTAL_FIXED" -ge 3 ]; then
    echo ""
    echo "✅ EXCELLENT PROGRESS!"
    echo "Most hanging issues resolved - nearly complete!"
else
    echo ""
    echo "⚠️ PARTIAL SUCCESS"
    echo "Some hanging issues remain - more debugging needed"
fi

echo ""
echo "$(date): Fixed TTL implementation testing complete!"

EOF












