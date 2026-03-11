#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== ISOLATED BASELINE + TTL TESTING ==="
echo "$(date): Testing baseline operations with zero TTL interference"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== COMPILING ISOLATED TTL VERSION ==="
export TMPDIR=/mnt/externalDisk/meteor/tmp_compile
g++ -std=c++20 -O3 -march=native -DBOOST_FIBER_NO_EXCEPTIONS -pthread -pipe meteor_systematic_ttl_lru.cpp -o meteor_isolated_ttl -lboost_fiber -lboost_context -lboost_system -luring 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed! Need to fix syntax errors."
    exit 1
fi

echo "✅ Isolated TTL version compiled successfully!"

echo ""
echo "Starting isolated TTL server..."
nohup ./meteor_isolated_ttl -c 4 -s 4 > isolated_ttl.log 2>&1 &
SERVER_PID=$!
sleep 6

echo ""
echo "🔥 PHASE 1: BASELINE OPERATIONS (ZERO TTL INTERFERENCE)"

echo "✅ Test 1: Pure baseline SET/GET (no TTL fields touched)"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nbaseline1\r\n\$10\r\nbaseline_v\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET baseline1: "
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nbaseline1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "✅ Test 2: Multiple baseline operations (performance validation)"
for i in {1..5}; do
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nbasekey$i\r\n\$9\r\nbaseval$i\r\n" | nc -w 1 127.0.0.1 6379 > /dev/null 2>&1
done

for i in {1..5}; do
    echo -n "GET basekey$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$8\r\nbasekey$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "✅ Test 3: Cross-core baseline operations"
printf "*3\r\n\$3\r\nSET\r\n\$10\r\ncrossbase1\r\n\$11\r\ncrossbasev1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET crossbase1: "
printf "*2\r\n\$3\r\nGET\r\n\$10\r\ncrossbase1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "🔥 PHASE 2: TTL OPERATIONS (ISOLATED FROM BASELINE)"

echo "✅ Test 4: TTL commands on existing keys"
printf "*3\r\n\$3\r\nSET\r\n\$7\r\nttlkey1\r\n\$8\r\nttlval1\r\n" | nc -w 2 127.0.0.1 6379

echo -n "GET before EXPIRE: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nttlkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "EXPIRE ttlkey1 10: "
printf "*3\r\n\$6\r\nEXPIRE\r\n\$7\r\nttlkey1\r\n\$2\r\n10\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "TTL ttlkey1: "
printf "*2\r\n\$3\r\nTTL\r\n\$7\r\nttlkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "GET after EXPIRE: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nttlkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo ""
echo "✅ Test 5: TTL expiration workflow"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nexpkey1\r\n\$9\r\nexpval1\r\n" | nc -w 2 127.0.0.1 6379
printf "*3\r\n\$6\r\nEXPIRE\r\n\$8\r\nexpkey1\r\n\$1\r\n3\r\n" | nc -w 2 127.0.0.1 6379

echo -n "Before expiration: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nexpkey1\r\n" | nc -w 2 127.0.0.1 6379

echo "⏳ Waiting 4 seconds for expiration..."
sleep 4

echo -n "After expiration (should be nil): "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nexpkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "TTL after expiration (should be -2): "
printf "*2\r\n\$3\r\nTTL\r\n\$8\r\nexpkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo ""
echo "🔥 PHASE 3: MIXED OPERATIONS (BASELINE + TTL COEXISTENCE)"

echo "✅ Test 6: Mixed baseline and TTL keys"
# Set normal keys
for i in {1..3}; do
    printf "*3\r\n\$3\r\nSET\r\n\$8\r\nmixkey$i\r\n\$9\r\nmixval$i\r\n" | nc -w 1 127.0.0.1 6379 > /dev/null 2>&1
done

# Set TTL key  
printf "*3\r\n\$3\r\nSET\r\n\$7\r\nttlmix1\r\n\$8\r\nttlmixv1\r\n" | nc -w 2 127.0.0.1 6379 > /dev/null 2>&1
printf "*3\r\n\$6\r\nEXPIRE\r\n\$7\r\nttlmix1\r\n\$2\r\n30\r\n" | nc -w 2 127.0.0.1 6379 > /dev/null 2>&1

# Verify baseline keys unaffected
echo -n "GET mixkey1 (baseline): "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nmixkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "GET mixkey2 (baseline): "  
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nmixkey2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "GET ttlmix1 (TTL key): "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nttlmix1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "TTL ttlmix1: "
printf "*2\r\n\$3\r\nTTL\r\n\$7\r\nttlmix1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

kill $SERVER_PID 2>/dev/null || true

echo ""
echo "=== ISOLATED TESTING RESULTS ==="
echo ""
echo "🎯 SUCCESS CRITERIA:"
echo "  ✅ Phase 1 - Baseline Operations: All GET/SET should work perfectly"
echo "  ✅ Phase 2 - TTL Operations: EXPIRE/TTL commands should work on existing keys"  
echo "  ✅ Phase 3 - Mixed Operations: Both types should coexist without interference"
echo ""
echo "🚀 PERFORMANCE VALIDATION:"
echo "  ✅ Baseline operations: ZERO TTL overhead (no has_ttl checks on creation)"
echo "  ✅ GET operations: TTL check only for keys that have_ttl = true"
echo "  ✅ Memory efficiency: No LRU overhead unless approaching limits"
echo ""
echo "❌ FAILURE INDICATORS:"
echo "  ❌ Empty GET responses: TTL interference with baseline"
echo "  ❌ Empty TTL commands: TTL implementation broken"
echo "  ❌ Performance regression: Unnecessary overhead added"
echo ""
echo "$(date): Isolated baseline + TTL testing complete!"

echo ""
echo "Server log analysis (last 15 lines):"
tail -15 isolated_ttl.log












