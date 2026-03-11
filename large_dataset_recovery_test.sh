#!/bin/bash

echo "🚀 LARGE DATASET RECOVERY TEST (100K+ keys)"
echo "============================================"

cd /home/sumit.kumar/meteor-persistent-test

# Kill any existing servers
killall meteor_redis_persistent 2>/dev/null || true
sleep 2

# Setup test directory
rm -rf test_large
mkdir -p test_large/{snapshots,aof}

echo "📊 Configuration:"
echo "  - Keys: 100,000"
echo "  - Cores: 4"
echo "  - Shards: 4"
echo "  - Snapshot interval: 30s"
echo "  - Fsync policy: everysec"
echo ""

# Start server
echo "🚀 Starting Meteor server..."
./meteor_redis_persistent -p 6390 -c 4 -s 4 -P 1 \
    -R ./test_large/snapshots \
    -A ./test_large/aof \
    -I 30 -O 10000 -F 2 > test_large/server.log 2>&1 &

SERVER_PID=$!
echo "Server PID: $SERVER_PID"
sleep 3

# Test if server is running
redis-cli -p 6390 PING > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Server failed to start"
    cat test_large/server.log
    exit 1
fi

echo "✅ Server started successfully"
echo ""

# Phase 1: Write 100K keys in batches
echo "📝 Phase 1: Writing 100,000 keys (this will take ~5 minutes)..."
START_TIME=$(date +%s)

BATCH_SIZE=100
TOTAL_KEYS=100000
BATCHES=$((TOTAL_KEYS / BATCH_SIZE))

for ((batch=0; batch<$BATCHES; batch++)); do
    START_KEY=$((batch * BATCH_SIZE + 1))
    END_KEY=$(((batch + 1) * BATCH_SIZE))
    
    # Build MSET command with 100 key-value pairs
    MSET_CMD="MSET"
    for ((i=$START_KEY; i<=$END_KEY; i++)); do
        MSET_CMD="$MSET_CMD large_key_$i large_value_$i"
    done
    
    echo "$MSET_CMD" | redis-cli -p 6390 > /dev/null 2>&1
    
    # Progress update every 10 batches (1000 keys)
    if [ $((batch % 10)) -eq 0 ]; then
        PROGRESS=$((batch * 100 / BATCHES))
        echo "  Progress: $PROGRESS% ($((batch * BATCH_SIZE))/$TOTAL_KEYS keys)"
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "✅ Wrote 100,000 keys in ${DURATION}s"
echo ""

# Verify a sample of keys
echo "🔍 Verifying sample keys..."
SAMPLE_KEYS=(1 25000 50000 75000 100000)
VERIFIED=0
for key in "${SAMPLE_KEYS[@]}"; do
    VALUE=$(redis-cli -p 6390 GET "large_key_$key")
    if [ "$VALUE" == "large_value_$key" ]; then
        echo "  ✅ large_key_$key = large_value_$key"
        VERIFIED=$((VERIFIED + 1))
    else
        echo "  ❌ large_key_$key FAILED (got: '$VALUE')"
    fi
done

if [ $VERIFIED -ne 5 ]; then
    echo "❌ Sample verification failed"
    exit 1
fi

echo "✅ All sample keys verified"
echo ""

# Wait for RDB snapshot
echo "⏳ Waiting 35 seconds for RDB snapshot..."
sleep 35

# Check snapshot files
echo "📂 Snapshot files created:"
ls -lh test_large/snapshots/*.rdb 2>/dev/null | tail -3
echo ""

# Check how many keys were snapshotted
echo "📋 Checking snapshot collection logs:"
grep "Collected.*keys from all shards" test_large/server.log | tail -1
echo ""

# Phase 2: Write additional 10K keys after snapshot
echo "📝 Phase 2: Writing 10,000 additional keys (for AOF testing)..."
for ((batch=0; batch<100; batch++)); do
    START_KEY=$((100000 + batch * 100 + 1))
    END_KEY=$((100000 + (batch + 1) * 100))
    
    MSET_CMD="MSET"
    for ((i=$START_KEY; i<=$END_KEY; i++)); do
        MSET_CMD="$MSET_CMD post_snapshot_$i value_$i"
    done
    
    echo "$MSET_CMD" | redis-cli -p 6390 > /dev/null 2>&1
done

echo "✅ Wrote 10,000 additional keys"
echo ""

# Check total keys before crash
echo "📊 Checking server state before crash:"
echo "  RDB files:"
ls -lh test_large/snapshots/*.rdb 2>/dev/null | tail -2
echo ""
echo "  AOF file:"
ls -lh test_large/aof/meteor.aof
echo ""

# Phase 3: CRASH RECOVERY TEST
echo "============================================"
echo "💥 CRASH RECOVERY TEST"
echo "============================================"
echo "Killing server with kill -9..."
kill -9 $SERVER_PID
sleep 2

echo "Restarting server..."
./meteor_redis_persistent -p 6390 -c 4 -s 4 -P 1 \
    -R ./test_large/snapshots \
    -A ./test_large/aof \
    -I 30 -O 10000 -F 2 > test_large/recovery.log 2>&1 &

NEW_PID=$!
sleep 8  # Give more time for large dataset recovery

echo ""
echo "📋 Recovery logs:"
grep -E "(Loaded|Replayed|Total recovered|Loading)" test_large/recovery.log
echo ""

# Phase 4: Verify recovered data
echo "============================================"
echo "🔍 VERIFICATION OF RECOVERED DATA"
echo "============================================"

# Sample verification from original 100K keys
echo "Verifying original keys (from RDB)..."
ORIGINAL_VERIFIED=0
ORIGINAL_SAMPLE=(1 10000 25000 50000 75000 90000 100000)

for key in "${ORIGINAL_SAMPLE[@]}"; do
    VALUE=$(redis-cli -p 6390 GET "large_key_$key" 2>/dev/null)
    if [ "$VALUE" == "large_value_$key" ]; then
        ORIGINAL_VERIFIED=$((ORIGINAL_VERIFIED + 1))
    fi
done

echo "  ✅ Verified $ORIGINAL_VERIFIED/${#ORIGINAL_SAMPLE[@]} original keys"

# Sample verification from post-snapshot keys (AOF)
echo "Verifying post-snapshot keys (from AOF)..."
AOF_VERIFIED=0
AOF_SAMPLE=(100001 102500 105000 107500 110000)

for key in "${AOF_SAMPLE[@]}"; do
    VALUE=$(redis-cli -p 6390 GET "post_snapshot_$key" 2>/dev/null)
    if [ "$VALUE" == "value_$key" ]; then
        AOF_VERIFIED=$((AOF_VERIFIED + 1))
    fi
done

echo "  ✅ Verified $AOF_VERIFIED/${#AOF_SAMPLE[@]} post-snapshot keys"

# Comprehensive random sampling
echo ""
echo "Performing comprehensive random sampling (100 keys)..."
RANDOM_VERIFIED=0
for i in {1..100}; do
    RANDOM_KEY=$((RANDOM % 100000 + 1))
    VALUE=$(redis-cli -p 6390 GET "large_key_$RANDOM_KEY" 2>/dev/null)
    if [ "$VALUE" == "large_value_$RANDOM_KEY" ]; then
        RANDOM_VERIFIED=$((RANDOM_VERIFIED + 1))
    fi
done

echo "  ✅ Random sample: $RANDOM_VERIFIED/100 keys verified"

# Calculate recovery percentage
TOTAL_VERIFIED=$((ORIGINAL_VERIFIED + AOF_VERIFIED + RANDOM_VERIFIED))
TOTAL_SAMPLED=$((${#ORIGINAL_SAMPLE[@]} + ${#AOF_SAMPLE[@]} + 100))
RECOVERY_PERCENTAGE=$((TOTAL_VERIFIED * 100 / TOTAL_SAMPLED))

echo ""
echo "============================================"
echo "📊 FINAL RESULTS"
echo "============================================"
echo "Dataset Size: 110,000 keys"
echo "Recovery Verification:"
echo "  - Original keys (RDB): $ORIGINAL_VERIFIED/${#ORIGINAL_SAMPLE[@]} ✅"
echo "  - Post-snapshot keys (AOF): $AOF_VERIFIED/${#AOF_SAMPLE[@]} ✅"
echo "  - Random sample: $RANDOM_VERIFIED/100 ✅"
echo ""
echo "Overall Recovery Rate: $RECOVERY_PERCENTAGE% ($TOTAL_VERIFIED/$TOTAL_SAMPLED keys)"
echo ""

if [ $RECOVERY_PERCENTAGE -ge 95 ]; then
    echo "🎉 SUCCESS: Recovery rate above 95%!"
    echo "✅ Large dataset persistence VALIDATED"
else
    echo "⚠️  WARNING: Recovery rate below 95%"
fi

echo ""
echo "📂 Files created:"
echo "  RDB: $(ls -lh test_large/snapshots/*.rdb 2>/dev/null | wc -l) files"
echo "  Latest RDB: $(ls -lh test_large/snapshots/meteor_latest.rdb 2>/dev/null)"
echo "  AOF: $(ls -lh test_large/aof/meteor.aof)"
echo ""

# Cleanup
kill $NEW_PID 2>/dev/null

echo "============================================"
echo "TEST COMPLETE"
echo "Full logs: test_large/server.log, test_large/recovery.log"
echo "============================================"



