#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=== TESTING GET-FIXED VERSION ==="
echo "$(date): Testing fully fixed version with working GET processing"

# Kill any running servers
pkill -f meteor 2>/dev/null || true
sleep 2

echo ""
echo "=== TESTING FULLY FIXED OPTIMIZED SERVER ==="
echo "Starting fully fixed server..."
nohup ./cpp/meteor_phase1_fully_fixed -c 4 -s 4 > fixed_server.log 2>&1 &
FIXED_PID=$!
echo "Fixed server PID: $FIXED_PID"
sleep 8

echo "Testing basic functionality:"
echo -n "SET simple: "
printf "*3\r\n\$3\r\nSET\r\n\$6\r\nsimple\r\n\$10\r\nsimplevalue\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET simple: "
printf "*2\r\n\$3\r\nGET\r\n\$6\r\nsimple\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing cross-core commands (this was hanging before):"
echo -n "SET cross-core: "
printf "*3\r\n\$3\r\nSET\r\n\$12\r\ncrosscorekey\r\n\$13\r\ncrosscore123\r\n" | nc -w 3 127.0.0.1 6379
echo -n "GET cross-core: "
printf "*2\r\n\$3\r\nGET\r\n\$12\r\ncrosscorekey\r\n" | nc -w 3 127.0.0.1 6379

echo ""
echo "Testing multiple different keys:"
for i in {1..3}; do
    echo "Testing fixedkey$i:"
    echo -n "SET: "
    printf "*3\r\n\$3\r\nSET\r\n\$9\r\nfixedkey$i\r\n\$11\r\nfixedvalue$i\r\n" | nc -w 2 127.0.0.1 6379
    echo -n "GET: "
    printf "*2\r\n\$3\r\nGET\r\n\$9\r\nfixedkey$i\r\n" | nc -w 2 127.0.0.1 6379
    echo "---"
done

echo ""
echo "Testing non-existent key:"
echo -n "GET nonexistent: "
printf "*2\r\n\$3\r\nGET\r\n\$11\r\nnonexistent\r\n" | nc -w 2 127.0.0.1 6379

kill $FIXED_PID 2>/dev/null || true

echo ""
echo "=== EXPECTED RESULTS (if GET is fixed) ==="
echo "✅ SET commands should return +OK"  
echo "✅ GET commands should return actual values like: \$10<CRLF>simplevalue<CRLF>"
echo "✅ GET nonexistent should return \$-1<CRLF>"
echo "✅ No hanging or empty responses"
echo ""
echo "$(date): GET-fixed version test complete"












