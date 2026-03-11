#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== MEMORY FIX VALIDATION TEST ==="
echo "$(date): Testing fixed BatchOperation memory issue"

pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== COMPILING MEMORY-FIXED VERSION ==="
export TMPDIR=/mnt/externalDisk/meteor/tmp_compile
g++ -std=c++20 -O3 -march=native -DBOOST_FIBER_NO_EXCEPTIONS -pthread -pipe meteor_systematic_ttl_lru.cpp -o meteor_memory_fixed -lboost_fiber -lboost_context -lboost_system -luring 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed!"
    exit 1
fi

echo "✅ Memory-fixed version compiled successfully!"

echo ""
echo "Starting memory-fixed server..."
nohup ./meteor_memory_fixed -c 4 -s 4 > memory_fixed.log 2>&1 &
SERVER_PID=$!
sleep 6

echo ""
echo "🔥 CRITICAL MEMORY FIX VALIDATION"

echo "✅ Test 1: Basic SET/GET (should now work correctly!)"
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nfixtest1\r\n\$9\r\nfixvalue1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "GET fixtest1: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nfixtest1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo ""
echo "✅ Test 2: Multiple SET/GET operations"
for i in {1..3}; do
    printf "*3\r\n\$3\r\nSET\r\n\$7\r\nmemkey$i\r\n\$8\r\nmemval$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET memkey$i: "
    printf "*2\r\n\$3\r\nGET\r\n\$7\r\nmemkey$i\r\n" | timeout 2s nc -w 2 127.0.0.1 6379
done

echo ""
echo "✅ Test 3: TTL commands with actual values"
printf "*3\r\n\$3\r\nSET\r\n\$7\r\nttlkey1\r\n\$8\r\nttlval1\r\n" | nc -w 2 127.0.0.1 6379

echo -n "GET before EXPIRE: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nttlkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "EXPIRE ttlkey1 15: "
printf "*3\r\n\$6\r\nEXPIRE\r\n\$7\r\nttlkey1\r\n\$2\r\n15\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "TTL ttlkey1: "
printf "*2\r\n\$3\r\nTTL\r\n\$7\r\nttlkey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

echo -n "GET after EXPIRE: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\nttlkey1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo ""
echo "✅ Test 4: TTL expiration validation"
printf "*3\r\n\$3\r\nSET\r\n\$9\r\nexptest1\r\n\$10\r\nexpvalue1\r\n" | nc -w 2 127.0.0.1 6379
printf "*3\r\n\$6\r\nEXPIRE\r\n\$9\r\nexptest1\r\n\$1\r\n3\r\n" | nc -w 2 127.0.0.1 6379

echo -n "GET before expiration: "
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nexptest1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo "⏳ Waiting 4 seconds for expiration..."
sleep 4

echo -n "GET after expiration: "
printf "*2\r\n\$3\r\nGET\r\n\$9\r\nexptest1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo -n "TTL after expiration: "
printf "*2\r\n\$3\r\nTTL\r\n\$9\r\nexptest1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo ""
echo "✅ Test 5: PERSIST command validation"
printf "*3\r\n\$3\r\nSET\r\n\$10\r\nperstest1\r\n\$11\r\npersvalue1\r\n" | nc -w 2 127.0.0.1 6379
printf "*3\r\n\$6\r\nEXPIRE\r\n\$10\r\nperstest1\r\n\$2\r\n60\r\n" | nc -w 2 127.0.0.1 6379

echo -n "TTL before PERSIST: "
printf "*2\r\n\$3\r\nTTL\r\n\$10\r\nperstest1\r\n" | nc -w 2 127.0.0.1 6379

echo -n "PERSIST result: "
printf "*2\r\n\$7\r\nPERSIST\r\n\$10\r\nperstest1\r\n" | nc -w 2 127.0.0.1 6379

echo -n "TTL after PERSIST: "
printf "*2\r\n\$3\r\nTTL\r\n\$10\r\nperstest1\r\n" | nc -w 2 127.0.0.1 6379

echo -n "GET after PERSIST: "
printf "*2\r\n\$3\r\nGET\r\n\$10\r\nperstest1\r\n" | timeout 2s nc -w 2 127.0.0.1 6379

echo ""
echo "✅ Test 6: Cross-core operations"
printf "*3\r\n\$3\r\nSET\r\n\$10\r\ncrosskey1\r\n\$11\r\ncrossval1\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Cross-core GET: "
printf "*2\r\n\$3\r\nGET\r\n\$10\r\ncrosskey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

printf "*3\r\n\$6\r\nEXPIRE\r\n\$10\r\ncrosskey1\r\n\$2\r\n30\r\n" | nc -w 2 127.0.0.1 6379
echo -n "Cross-core TTL: "
printf "*2\r\n\$3\r\nTTL\r\n\$10\r\ncrosskey1\r\n" | timeout 3s nc -w 3 127.0.0.1 6379

kill $SERVER_PID 2>/dev/null || true

echo ""
echo "=== MEMORY FIX VALIDATION RESULTS ==="
echo ""
echo "🏆 EXPECTED RESULTS AFTER MEMORY FIX:"
echo "  ✅ GET operations: Should return actual values, not \$0"
echo "  ✅ SET/GET consistency: Values should be preserved correctly"
echo "  ✅ TTL commands: Should work with actual stored values"
echo "  ✅ Expiration: Should work correctly with real values"
echo "  ✅ Cross-core: Should handle routing with correct values"
echo ""
echo "❌ REGRESSION INDICATORS:"
echo "  ❌ GET returns \$0: Memory issue not fully fixed"
echo "  ❌ Empty responses: Command processing still broken"
echo "  ❌ Server crashes: New issues introduced"
echo ""
echo "🚀 SUCCESS INDICATORS:"
echo "  🎯 GET returns proper bulk strings: \$N\\r\\nVALUE\\r\\n"
echo "  🎯 TTL commands work with stored values"
echo "  🎯 Expiration works correctly"
echo "  🎯 PERSIST preserves actual values"
echo ""
echo "$(date): Memory fix validation complete!"

echo ""
echo "Server log (last 15 lines):"
tail -15 memory_fixed.log












