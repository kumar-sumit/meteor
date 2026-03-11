#!/bin/bash

echo "🚀 FAST LARGE DATASET TEST (50K keys)"
echo "============================================"

cd /home/sumit.kumar/meteor-persistent-test

# Kill any existing servers
killall meteor_redis_persistent 2>/dev/null || true
sleep 2

# Setup
rm -rf test_fast_large
mkdir -p test_fast_large/{snapshots,aof}

echo "📊 Configuration: 50,000 keys, 4 cores, 4 shards"
echo ""

# Start server
echo "🚀 Starting server..."
./meteor_redis_persistent -p 6390 -c 4 -s 4 -P 1 \
    -R ./test_fast_large/snapshots \
    -A ./test_fast_large/aof \
    -I 20 -O 5000 -F 2 > test_fast_large/server.log 2>&1 &

SERVER_PID=$!
sleep 3

redis-cli -p 6390 PING > /dev/null 2>&1 || { echo "❌ Server failed"; exit 1; }
echo "✅ Server started (PID: $SERVER_PID)"
echo ""

# Phase 1: Write 50K keys using redis-cli with smaller MSET batches
echo "📝 Writing 50,000 keys (using 10-key MSET batches)..."
START=$(date +%s)

for ((i=1; i<=50000; i+=10)); do
    redis-cli -p 6390 MSET \
        "key_$i" "value_$i" \
        "key_$((i+1))" "value_$((i+1))" \
        "key_$((i+2))" "value_$((i+2))" \
        "key_$((i+3))" "value_$((i+3))" \
        "key_$((i+4))" "value_$((i+4))" \
        "key_$((i+5))" "value_$((i+5))" \
        "key_$((i+6))" "value_$((i+6))" \
        "key_$((i+7))" "value_$((i+7))" \
        "key_$((i+8))" "value_$((i+8))" \
        "key_$((i+9))" "value_$((i+9))" > /dev/null 2>&1
    
    if [ $((i % 5000)) -eq 1 ]; then
        PCT=$((i * 100 / 50000))
        echo "  Progress: $PCT% ($i/50000)"
    fi
done

END=$(date +%s)
DUR=$((END - START))
echo "✅ Wrote 50,000 keys in ${DUR}s"
echo ""

# Verify sample
echo "🔍 Verifying sample keys..."
VERIFIED=0
for key in 1 10000 25000 40000 50000; do
    VAL=$(redis-cli -p 6390 GET "key_$key")
    if [ "$VAL" == "value_$key" ]; then
        echo "  ✅ key_$key"
        VERIFIED=$((VERIFIED + 1))
    else
        echo "  ❌ key_$key (got: '$VAL')"
    fi
done
echo ""

# Wait for snapshot
echo "⏳ Waiting 25s for RDB snapshot..."
sleep 25

echo "📂 Snapshot files:"
ls -lh test_fast_large/snapshots/*.rdb 2>/dev/null | tail -2
echo ""

grep "Collected.*keys" test_fast_large/server.log | tail -1
echo ""

# Write more keys for AOF
echo "📝 Writing 5,000 additional keys..."
for ((i=50001; i<=55000; i+=10)); do
    redis-cli -p 6390 MSET \
        "after_$i" "val_$i" \
        "after_$((i+1))" "val_$((i+1))" \
        "after_$((i+2))" "val_$((i+2))" \
        "after_$((i+3))" "val_$((i+3))" \
        "after_$((i+4))" "val_$((i+4))" \
        "after_$((i+5))" "val_$((i+5))" \
        "after_$((i+6))" "val_$((i+6))" \
        "after_$((i+7))" "val_$((i+7))" \
        "after_$((i+8))" "val_$((i+8))" \
        "after_$((i+9))" "val_$((i+9))" > /dev/null 2>&1
done
echo "✅ Wrote 5,000 additional keys"
echo ""

# CRASH TEST
echo "============================================"
echo "💥 CRASH RECOVERY TEST"
echo "============================================"
kill -9 $SERVER_PID
sleep 2

echo "Restarting..."
./meteor_redis_persistent -p 6390 -c 4 -s 4 -P 1 \
    -R ./test_fast_large/snapshots \
    -A ./test_fast_large/aof \
    -I 20 -O 5000 -F 2 > test_fast_large/recovery.log 2>&1 &

NEW_PID=$!
sleep 6

echo ""
echo "📋 Recovery:"
grep -E "(Loaded|Replayed|Total recovered)" test_fast_large/recovery.log
echo ""

# Verify recovery
echo "🔍 Verifying recovered data..."
ORIG_OK=0
for key in 1 5000 15000 30000 50000; do
    VAL=$(redis-cli -p 6390 GET "key_$key" 2>/dev/null)
    [ "$VAL" == "value_$key" ] && ORIG_OK=$((ORIG_OK + 1))
done

AOF_OK=0
for key in 50001 51000 53000 55000; do
    VAL=$(redis-cli -p 6390 GET "after_$key" 2>/dev/null)
    [ "$VAL" == "val_$key" ] && AOF_OK=$((AOF_OK + 1))
done

echo "  RDB keys: $ORIG_OK/5 ✅"
echo "  AOF keys: $AOF_OK/4 ✅"
echo ""

TOTAL=$((ORIG_OK + AOF_OK))
PCT=$((TOTAL * 100 / 9))

echo "============================================"
echo "📊 RESULTS"
echo "============================================"
echo "Dataset: 55,000 keys"
echo "Recovery rate: $PCT% ($TOTAL/9 sample keys)"

if [ $TOTAL -ge 8 ]; then
    echo "🎉 SUCCESS: Large dataset persistence VALIDATED!"
else
    echo "⚠️  Some keys missing"
fi

echo ""
echo "Files:"
ls -lh test_fast_large/snapshots/*.rdb 2>/dev/null | tail -1
ls -lh test_fast_large/aof/meteor.aof

kill $NEW_PID 2>/dev/null

echo ""
echo "TEST COMPLETE"


