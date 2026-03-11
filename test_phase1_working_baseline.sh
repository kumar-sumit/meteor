#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== PHASE 1 OPTIMIZED WORKING BASELINE TEST ==="
echo "$(date): Testing Phase 1 optimizations on proven working baseline"

# Kill any running servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== WORKING BASELINE TEST ===" 
echo "Starting working baseline meteor_final_correct..."
nohup ./cpp/meteor_final_correct -c 4 -s 4 > working_baseline_test.log 2>&1 &
BASELINE_PID=$!
echo "Baseline server PID: $BASELINE_PID"
sleep 8

echo "Testing working baseline:"
echo -n "SET baseline: "
printf "*3\r\n\$3\r\nSET\r\n\$8\r\nworkkey1\r\n\$9\r\nworkval1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET baseline: "
printf "*2\r\n\$3\r\nGET\r\n\$8\r\nworkkey1\r\n" | nc -w 3 127.0.0.1 6379

kill $BASELINE_PID 2>/dev/null || true
sleep 3

echo ""
echo "=== PHASE 1 OPTIMIZED TEST ==="
echo "Starting Phase 1 optimized version..."
nohup ./cpp/meteor_phase1_optimized_working -c 4 -s 4 > phase1_optimized_test.log 2>&1 &
OPTIMIZED_PID=$!
echo "Optimized server PID: $OPTIMIZED_PID"
sleep 8

echo "Testing Phase 1 optimized version:"
echo -n "SET optimized: "
printf "*3\r\n\$3\r\nSET\r\n\$7\r\noptkey1\r\n\$8\r\noptval1\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET optimized: "
printf "*2\r\n\$3\r\nGET\r\n\$7\r\noptkey1\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing cross-core commands:"
echo -n "SET cross-core: "
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscorekey\r\n\$13\r\ncrosscoreval\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET cross-core: "
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorekey\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing multiple keys:"
for i in {1..5}; do
    echo -n "SET/GET key$i: "
    printf "*3\r\n\$3\r\nSET\r\n\$4\r\nkey$i\r\n\$6\r\nvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    printf "*2\r\n\$3\r\nGET\r\n\$4\r\nkey$i\r\n" | nc -w 2 127.0.0.1 6379
    echo ""
done

kill $OPTIMIZED_PID 2>/dev/null || true

echo ""
echo "=== VALIDATION RESULTS ==="
echo "Expected Results:"
echo "✅ SET commands return +OK"  
echo "✅ GET commands return actual values (not \$-1 or nil)"
echo "✅ No commands hang or timeout"
echo "✅ Cross-core commands work correctly"
echo ""
echo "$(date): Phase 1 correctness test complete"












