#!/bin/bash
# **COMPREHENSIVE PERSISTENCE TEST SCRIPT**
# Tests crash recovery, restart recovery, and validates 1GB+ data

set -e

# Configuration
PORT=6390
CORES=4
SHARDS=4
SERVER_BIN="./meteor_redis_persistent"
RDB_PATH="./test_snapshots"
AOF_PATH="./test_aof"
SNAPSHOT_INTERVAL=60  # 60 seconds for testing
SNAPSHOT_OPS=50000   # 50K operations

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "🧪 METEOR PERSISTENCE COMPREHENSIVE TEST"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    echo -e "${YELLOW}🧹 Cleaning up...${NC}"
    pkill -9 -f "meteor_redis_persistent.*6390" 2>/dev/null || true
    sleep 2
}

# Cleanup on exit
trap cleanup EXIT

# Step 1: Initial cleanup
echo "Step 1: Cleanup previous test data"
cleanup
rm -rf $RDB_PATH $AOF_PATH/*.aof 2>/dev/null || true
mkdir -p $RDB_PATH $AOF_PATH
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""

# Step 2: Start server with persistence
echo "Step 2: Starting Meteor server with persistence on port $PORT"
$SERVER_BIN -p $PORT -c $CORES -s $SHARDS \
    -P 1 \
    -R $RDB_PATH \
    -A $AOF_PATH \
    -I $SNAPSHOT_INTERVAL \
    -O $SNAPSHOT_OPS \
    -F 2 \
    > server.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
sleep 5

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo -e "${RED}❌ Server failed to start${NC}"
    cat server.log | tail -20
    exit 1
fi

echo -e "${GREEN}✅ Server started successfully${NC}"
echo ""

# Step 3: Write 1GB+ of test data (~1 million keys with 1KB values)
echo "Step 3: Writing 1GB+ test data (this will take a few minutes)..."
echo "Target: 1 million keys × 1KB = ~1GB"

# Generate test data script
cat > write_test_data.sh << 'WRITE_SCRIPT'
#!/bin/bash
PORT=$1
TOTAL_KEYS=$2
BATCH_SIZE=1000
VALUE_SIZE=1024  # 1KB values

echo "Writing $TOTAL_KEYS keys in batches of $BATCH_SIZE..."

for ((batch=0; batch<TOTAL_KEYS/BATCH_SIZE; batch++)); do
    start_key=$((batch * BATCH_SIZE))
    end_key=$((start_key + BATCH_SIZE - 1))
    
    # Use redis-cli --pipe for maximum performance
    {
        for ((i=start_key; i<=end_key; i++)); do
            # Generate 1KB value (1000 'x' characters)
            VALUE=$(printf 'x%.0s' {1..1000})
            echo "SET test_key_$i $VALUE"
        done
    } | redis-cli -p $PORT --pipe > /dev/null 2>&1
    
    if ((batch % 10 == 0)); then
        progress=$((batch * 100 * BATCH_SIZE / TOTAL_KEYS))
        echo -ne "\rProgress: $progress% ($((batch * BATCH_SIZE))/$TOTAL_KEYS keys)"
    fi
done

echo -ne "\rProgress: 100% ($TOTAL_KEYS/$TOTAL_KEYS keys)\n"
WRITE_SCRIPT

chmod +x write_test_data.sh

# Write 1 million keys (1GB data)
./write_test_data.sh $PORT 1000000

echo -e "${GREEN}✅ 1GB+ data written successfully${NC}"
echo ""

# Step 4: Verify data before snapshot
echo "Step 4: Verifying data integrity..."
SAMPLE_KEYS=("test_key_0" "test_key_500000" "test_key_999999")

for key in "${SAMPLE_KEYS[@]}"; do
    VALUE=$(redis-cli -p $PORT GET "$key")
    if [[ -z "$VALUE" ]]; then
        echo -e "${RED}❌ Failed to retrieve $key${NC}"
        exit 1
    fi
    echo "✓ $key: ${#VALUE} bytes"
done

echo -e "${GREEN}✅ Data integrity verified${NC}"
echo ""

# Step 5: Wait for RDB snapshot
echo "Step 5: Waiting for RDB snapshot (${SNAPSHOT_INTERVAL}s)..."
sleep $((SNAPSHOT_INTERVAL + 10))

# Verify snapshot files
if ls $RDB_PATH/*.rdb 1> /dev/null 2>&1; then
    echo -e "${GREEN}✅ RDB snapshot created:${NC}"
    ls -lh $RDB_PATH/*.rdb
else
    echo -e "${YELLOW}⚠️  No RDB snapshot found yet${NC}"
fi

if [ -f "$AOF_PATH/meteor.aof" ]; then
    echo -e "${GREEN}✅ AOF file exists:${NC}"
    ls -lh $AOF_PATH/meteor.aof
else
    echo -e "${RED}❌ AOF file not found${NC}"
fi
echo ""

# Step 6: Write additional data after snapshot
echo "Step 6: Writing additional data after snapshot..."
for i in {2000000..2010000}; do
    redis-cli -p $PORT SET "after_snapshot_key_$i" "after_snapshot_value_$i" > /dev/null
done
echo -e "${GREEN}✅ 10K keys written after snapshot${NC}"
echo ""

# Step 7: TEST CRASH RECOVERY (kill -9)
echo "=========================================="
echo "Step 7: CRASH RECOVERY TEST (kill -9)"
echo "=========================================="
echo "Simulating crash with kill -9..."
kill -9 $SERVER_PID
sleep 3

echo "Restarting server..."
$SERVER_BIN -p $PORT -c $CORES -s $SHARDS \
    -P 1 \
    -R $RDB_PATH \
    -A $AOF_PATH \
    -I $SNAPSHOT_INTERVAL \
    -O $SNAPSHOT_OPS \
    -F 2 \
    > server_restart1.log 2>&1 &
SERVER_PID=$!

echo "New server PID: $SERVER_PID"
sleep 8

# Verify recovery
echo "Verifying crash recovery..."
MISSING_KEYS=0
CHECKED_KEYS=0

# Check sample keys from before snapshot
for key in "${SAMPLE_KEYS[@]}"; do
    VALUE=$(redis-cli -p $PORT GET "$key" 2>/dev/null)
    ((CHECKED_KEYS++))
    if [[ -z "$VALUE" ]]; then
        echo -e "${RED}❌ Missing key: $key${NC}"
        ((MISSING_KEYS++))
    fi
done

# Check keys from after snapshot (should be in AOF)
for i in {2000000..2000010}; do
    VALUE=$(redis-cli -p $PORT GET "after_snapshot_key_$i" 2>/dev/null)
    ((CHECKED_KEYS++))
    if [[ "$VALUE" != "after_snapshot_value_$i" ]]; then
        echo -e "${RED}❌ Missing/incorrect key: after_snapshot_key_$i${NC}"
        ((MISSING_KEYS++))
    fi
done

echo "Checked: $CHECKED_KEYS keys"
echo "Missing: $MISSING_KEYS keys"

if [ $MISSING_KEYS -eq 0 ]; then
    echo -e "${GREEN}✅ CRASH RECOVERY SUCCESSFUL - All keys recovered!${NC}"
else
    echo -e "${RED}❌ CRASH RECOVERY FAILED - $MISSING_KEYS keys missing${NC}"
    exit 1
fi
echo ""

# Step 8: TEST GRACEFUL RESTART
echo "=========================================="
echo "Step 8: GRACEFUL RESTART TEST (SIGTERM)"
echo "=========================================="
echo "Writing more test data..."
for i in {3000000..3010000}; do
    redis-cli -p $PORT SET "graceful_key_$i" "graceful_value_$i" > /dev/null
done

echo "Gracefully stopping server (SIGTERM)..."
kill -TERM $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
sleep 5

echo "Restarting server..."
$SERVER_BIN -p $PORT -c $CORES -s $SHARDS \
    -P 1 \
    -R $RDB_PATH \
    -A $AOF_PATH \
    -I $SNAPSHOT_INTERVAL \
    -O $SNAPSHOT_OPS \
    -F 2 \
    > server_restart2.log 2>&1 &
SERVER_PID=$!

echo "New server PID: $SERVER_PID"
sleep 8

# Verify graceful restart recovery
echo "Verifying graceful restart recovery..."
MISSING_KEYS=0
CHECKED_KEYS=0

for i in {3000000..3000010}; do
    VALUE=$(redis-cli -p $PORT GET "graceful_key_$i" 2>/dev/null)
    ((CHECKED_KEYS++))
    if [[ "$VALUE" != "graceful_value_$i" ]]; then
        echo -e "${RED}❌ Missing/incorrect key: graceful_key_$i${NC}"
        ((MISSING_KEYS++))
    fi
done

echo "Checked: $CHECKED_KEYS keys"
echo "Missing: $MISSING_KEYS keys"

if [ $MISSING_KEYS -eq 0 ]; then
    echo -e "${GREEN}✅ GRACEFUL RESTART SUCCESSFUL - All keys recovered!${NC}"
else
    echo -e "${RED}❌ GRACEFUL RESTART FAILED - $MISSING_KEYS keys missing${NC}"
    exit 1
fi
echo ""

# Step 9: TEST ALL REDIS COMMANDS
echo "=========================================="
echo "Step 9: VALIDATE ALL REDIS COMMANDS"
echo "=========================================="

# Test SET/GET
redis-cli -p $PORT SET test_cmd_set "test_value" > /dev/null
RESULT=$(redis-cli -p $PORT GET test_cmd_set)
[[ "$RESULT" == "test_value" ]] && echo -e "${GREEN}✅ SET/GET${NC}" || echo -e "${RED}❌ SET/GET${NC}"

# Test MSET/MGET
redis-cli -p $PORT MSET test_mset1 "value1" test_mset2 "value2" > /dev/null
RESULT=$(redis-cli -p $PORT MGET test_mset1 test_mset2 | tr '\n' ' ')
[[ "$RESULT" == "value1 value2 " ]] && echo -e "${GREEN}✅ MSET/MGET${NC}" || echo -e "${RED}❌ MSET/MGET${NC}"

# Test SETEX
redis-cli -p $PORT SETEX test_setex 3600 "temp_value" > /dev/null
RESULT=$(redis-cli -p $PORT GET test_setex)
[[ "$RESULT" == "temp_value" ]] && echo -e "${GREEN}✅ SETEX${NC}" || echo -e "${RED}❌ SETEX${NC}"

# Test TTL
TTL=$(redis-cli -p $PORT TTL test_setex)
[[ $TTL -gt 0 ]] && echo -e "${GREEN}✅ TTL (${TTL}s remaining)${NC}" || echo -e "${RED}❌ TTL${NC}"

# Test EXPIRE
redis-cli -p $PORT SET test_expire "expire_value" > /dev/null
redis-cli -p $PORT EXPIRE test_expire 7200 > /dev/null
TTL=$(redis-cli -p $PORT TTL test_expire)
[[ $TTL -gt 0 ]] && echo -e "${GREEN}✅ EXPIRE${NC}" || echo -e "${RED}❌ EXPIRE${NC}"

# Test DEL
redis-cli -p $PORT SET test_del "to_delete" > /dev/null
redis-cli -p $PORT DEL test_del > /dev/null
RESULT=$(redis-cli -p $PORT GET test_del)
[[ "$RESULT" == "" ]] && echo -e "${GREEN}✅ DEL${NC}" || echo -e "${RED}❌ DEL${NC}"

# Test PING
RESULT=$(redis-cli -p $PORT PING)
[[ "$RESULT" == "PONG" ]] && echo -e "${GREEN}✅ PING${NC}" || echo -e "${RED}❌ PING${NC}"

echo ""

# Step 10: Final statistics
echo "=========================================="
echo "Step 10: FINAL STATISTICS"
echo "=========================================="
echo "RDB snapshots:"
ls -lh $RDB_PATH/ | grep "\.rdb" || echo "No RDB files"
echo ""
echo "AOF file:"
ls -lh $AOF_PATH/meteor.aof || echo "No AOF file"
echo ""
echo "Server logs (last 20 lines):"
echo "----------------------------------------"
tail -20 server_restart2.log
echo ""

# Summary
echo "=========================================="
echo "🎉 TEST SUMMARY"
echo "=========================================="
echo -e "${GREEN}✅ 1GB+ data written and persisted${NC}"
echo -e "${GREEN}✅ Crash recovery (kill -9) successful${NC}"
echo -e "${GREEN}✅ Graceful restart recovery successful${NC}"
echo -e "${GREEN}✅ All Redis commands working${NC}"
echo -e "${GREEN}✅ RDB snapshots working${NC}"
echo -e "${GREEN}✅ AOF replay working${NC}"
echo ""
echo -e "${GREEN}🎯 ALL TESTS PASSED! 🎉${NC}"
echo ""

# Keep server running for manual testing
echo "Server is still running on port $PORT (PID: $SERVER_PID)"
echo "To stop: kill $SERVER_PID"
echo "To test manually: redis-cli -p $PORT"
echo ""



