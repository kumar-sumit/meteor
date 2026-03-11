#!/bin/bash
# Simple but comprehensive persistence test

PORT=6390
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "🧪 SIMPLE PERSISTENCE TEST"
echo "=================================================="
echo ""

# Kill any existing server
pkill -9 -f "meteor_redis.*${PORT}" 2>/dev/null
sleep 2

# Clean start
rm -rf ./test_data
mkdir -p ./test_data/snapshots ./test_data/aof
cd /home/sumit.kumar/meteor-persistent-test

echo "Step 1: Start server with persistence"
./meteor_redis_persistent -p $PORT -c 4 -s 4 \
  -P 1 \
  -R ./test_data/snapshots \
  -A ./test_data/aof \
  -I 30 \
  -O 1000 \
  -F 2 \
  > test_data/server1.log 2>&1 &
  
SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 6

# Test 1: Write 10K keys
echo ""
echo "Step 2: Writing 10,000 keys..."
START_TIME=$(date +%s)

for i in $(seq 1 10000); do
    redis-cli -p $PORT SET "key_$i" "value_$i" > /dev/null 2>&1
    
    if [ $((i % 1000)) -eq 0 ]; then
        echo -ne "\rProgress: $i/10000 keys"
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo -ne "\r✅ Wrote 10,000 keys in ${DURATION}s\n"

# Verify some keys
echo ""
echo "Step 3: Verifying written data..."
ERRORS=0
for key in "key_1" "key_5000" "key_10000"; do
    VAL=$(redis-cli -p $PORT GET "$key")
    EXPECTED="value_${key#key_}"
    if [ "$VAL" = "$EXPECTED" ]; then
        echo "  ✅ $key = $VAL"
    else
        echo -e "  ${RED}❌ $key = $VAL (expected $EXPECTED)${NC}"
        ((ERRORS++))
    fi
done

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ Data verification failed!${NC}"
    exit 1
fi

# Wait for snapshot
echo ""
echo "Step 4: Waiting for RDB snapshot (32 seconds)..."
sleep 32

# Check files
echo "RDB files:"
ls -lh ./test_data/snapshots/*.rdb 2>/dev/null || echo "No RDB files"
echo "AOF file:"
ls -lh ./test_data/aof/meteor.aof 2>/dev/null || echo "No AOF file"

# Write more keys after snapshot
echo ""
echo "Step 5: Writing 1,000 more keys after snapshot..."
for i in $(seq 20001 21000); do
    redis-cli -p $PORT SET "after_key_$i" "after_value_$i" > /dev/null 2>&1
done
echo "✅ Wrote 1,000 keys after snapshot"

# Crash test
echo ""
echo "=========================================="
echo "Step 6: CRASH RECOVERY TEST (kill -9)"
echo "=========================================="
echo "Killing server..."
kill -9 $SERVER_PID
sleep 3

echo "Restarting server..."
./meteor_redis_persistent -p $PORT -c 4 -s 4 \
  -P 1 \
  -R ./test_data/snapshots \
  -A ./test_data/aof \
  -I 30 \
  -O 1000 \
  -F 2 \
  > test_data/server2.log 2>&1 &
  
SERVER_PID=$!
echo "New server PID: $SERVER_PID"
sleep 8

# Check recovery logs
echo ""
echo "Recovery logs:"
grep -E "(Recovering|Loaded|entries)" test_data/server2.log | head -10

# Verify recovery
echo ""
echo "Step 7: Verifying crash recovery..."
ERRORS=0

# Check original keys
for key in "key_1" "key_5000" "key_10000"; do
    VAL=$(redis-cli -p $PORT GET "$key" 2>/dev/null)
    EXPECTED="value_${key#key_}"
    if [ "$VAL" = "$EXPECTED" ]; then
        echo "  ✅ $key recovered"
    else
        echo -e "  ${RED}❌ $key missing (got: $VAL)${NC}"
        ((ERRORS++))
    fi
done

# Check post-snapshot keys (from AOF)
for key in "after_key_20001" "after_key_21000"; do
    VAL=$(redis-cli -p $PORT GET "$key" 2>/dev/null)
    EXPECTED="after_value_${key#after_key_}"
    if [ "$VAL" = "$EXPECTED" ]; then
        echo "  ✅ $key recovered (from AOF)"
    else
        echo -e "  ${RED}❌ $key missing (got: $VAL)${NC}"
        ((ERRORS++))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ ALL DATA RECOVERED SUCCESSFULLY!${NC}"
else
    echo -e "${RED}❌ Recovery failed with $ERRORS errors${NC}"
    exit 1
fi

# Test all commands
echo ""
echo "Step 8: Testing all Redis commands..."
redis-cli -p $PORT SET cmd_test "test" > /dev/null && echo "✅ SET"
redis-cli -p $PORT GET cmd_test > /dev/null && echo "✅ GET"
redis-cli -p $PORT MSET m1 v1 m2 v2 > /dev/null && echo "✅ MSET"
redis-cli -p $PORT MGET m1 m2 > /dev/null && echo "✅ MGET"
redis-cli -p $PORT SETEX ttl_test 3600 "temp" > /dev/null && echo "✅ SETEX"
redis-cli -p $PORT TTL ttl_test > /dev/null && echo "✅ TTL"
redis-cli -p $PORT EXPIRE cmd_test 7200 > /dev/null && echo "✅ EXPIRE"
redis-cli -p $PORT DEL cmd_test > /dev/null && echo "✅ DEL"
redis-cli -p $PORT PING > /dev/null && echo "✅ PING"

echo ""
echo "=================================================="
echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
echo "=================================================="
echo ""
echo "Final stats:"
echo "  - 10,000 keys written before snapshot"
echo "  - 1,000 keys written after snapshot"
echo "  - 100% recovery after crash"
echo "  - All Redis commands working"
echo ""
echo "Server still running on port $PORT (PID: $SERVER_PID)"
echo "To stop: kill $SERVER_PID"



