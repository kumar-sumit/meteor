#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== CONSTRUCTOR FIX VALIDATION ==="
echo "$(date): Testing fixed VLLHashTable constructor"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== COMPILING CONSTRUCTOR-FIXED VERSION ==="
export TMPDIR=/mnt/externalDisk/meteor/tmp_compile
g++ -std=c++20 -O3 -march=native -DBOOST_FIBER_NO_EXCEPTIONS -pthread -pipe meteor_systematic_ttl_lru.cpp -o meteor_constructor_fixed -lboost_fiber -lboost_context -lboost_system -luring 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed! Showing errors:"
    g++ -std=c++20 -O3 -march=native -DBOOST_FIBER_NO_EXCEPTIONS -pthread -pipe meteor_systematic_ttl_lru.cpp -o meteor_constructor_fixed -lboost_fiber -lboost_context -lboost_system -luring
    exit 1
fi

echo "✅ Constructor-fixed version compiled successfully!"

echo ""
echo "Starting constructor-fixed server..."
nohup ./meteor_constructor_fixed -c 4 -s 4 > constructor_fixed.log 2>&1 &
SERVER_PID=$!
sleep 6

echo ""
echo "🔥 CONSTRUCTOR FIX VALIDATION TESTS"

echo "✅ Test 1: Basic SET/GET (constructor fix validation)"
printf "*3\r\n\$3\r\nSET\r\n\$7\r\nfixtest\r\n\$8\r\nfixvalue\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET fixtest: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nfixtest\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "✅ Test 2: Multiple operations (stability test)"
for i in {1..3}; do
    printf "*3\r\n\$3\r\nSET\r\n\$6\r\nstable$i\r\n\$7\r\nstabval$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET stable$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$6\r\nstable$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "✅ Test 3: TTL operations (now that constructor is fixed)"
printf "*3\r\n\$3\r\nSET\r\n\$7\r\nttltest\r\n\$8\r\nttlvalue\r\n" | nc -w 2 127.0.0.1 6379

echo -n "EXPIRE ttltest 15: "
printf "*3\r\n\$6\r\nEXPIRE\r\n\$7\r\nttltest\r\n\$2\r\n15\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "TTL ttltest: "
printf "*2\r\n\$3\r\nTTL\r\n\$7\r\nttltest\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "GET after EXPIRE: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nttltest\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo ""
echo "✅ Test 4: TTL expiration (complete workflow)"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nexptest2\r\n\$9\r\nexpvalue2\r\n" | nc -w 2 127.0.0.1 6379
printf "*3\r\n\$6\r\nEXPIRE\r\n\$8\r\nexptest2\r\n\$1\r\n3\r\n" | nc -w 2 127.0.0.1 6379

echo -n "Before expiration: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nexptest2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo "⏳ Waiting 4 seconds for expiration..."
sleep 4

echo -n "After expiration (should be nil): "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nexptest2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo ""
echo "✅ Test 5: PERSIST command"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nperstest2\r\n\$10\r\npersvalue2\r\n" | nc -w 2 127.0.0.1 6379
printf "*3\r\n\$6\r\nEXPIRE\r\n\$9\r\nperstest2\r\n\$2\r\n60\r\n" | nc -w 2 127.0.0.1 6379

echo -n "TTL before PERSIST: "
printf "*2\r\n\$3\r\nTTL\r\n\$9\r\nperstest2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "PERSIST result: "
printf "*2\r\n\$7\r\nPERSIST\r\n\$9\r\nperstest2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "TTL after PERSIST (-1 expected): "
printf "*2\r\n\$3\r\nTTL\r\n\$9\r\nperstest2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "GET after PERSIST: "
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nperstest2\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

kill $SERVER_PID 2>/dev/null || true

echo ""
echo "=== CONSTRUCTOR FIX VALIDATION RESULTS ==="
echo ""
echo "🏆 EXPECTED RESULTS AFTER CONSTRUCTOR FIX:"
echo "  ✅ Test 1: GET should return \$8\\r\\nfixvalue\\r\\n (not empty!)"
echo "  ✅ Test 2: All multiple operations should work consistently"
echo "  ✅ Test 3: TTL commands should return proper responses"
echo "  ✅ Test 4: TTL expiration should work correctly"
echo "  ✅ Test 5: PERSIST should work with proper TTL values"
echo ""
echo "🚀 SUCCESS INDICATORS:"
echo "  🎯 Consistent GET responses with actual values"
echo "  🎯 TTL commands return :N format (not empty)"
echo "  🎯 Server stability through multiple operations"
echo "  🎯 Proper Redis protocol compliance"
echo ""
echo "❌ FAILURE INDICATORS (if constructor still broken):"
echo "  ❌ Empty GET responses"
echo "  ❌ Empty TTL command responses"  
echo "  ❌ Server instability or crashes"
echo ""
echo "$(date): Constructor fix validation complete!"

echo ""
echo "Server log (last 10 lines):"
tail -10 constructor_fixed.log












