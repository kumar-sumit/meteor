#!/bin/bash

echo "🧪 SHARED-NOTHING MULTI-CORE TEST SUITE"
echo "========================================"
echo "🎯 Goal: Eliminate migration loops, achieve linear scaling"
echo ""

# Kill any existing servers
pkill -f meteor_shared_nothing 2>/dev/null || true
sleep 2

echo "🔧 Test 1: Single-core baseline (should maintain 135K+ RPS)"
echo "--------------------------------------------------------"
timeout 8 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 ./meteor_shared_nothing -h 127.0.0.1 -p 6390 -c 1' &
sleep 3
echo "Running single-core benchmark..."
redis-benchmark -p 6390 -c 10 -n 10000 -t set -q
echo ""
echo "Testing individual commands..."
redis-cli -p 6390 ping
redis-cli -p 6390 set key1 "value1"
redis-cli -p 6390 get key1
pkill -f meteor_shared_nothing
sleep 1

echo ""
echo "🔧 Test 2: 2-core with shared-nothing (no migration loops expected)"
echo "----------------------------------------------------------------"
timeout 10 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 ./meteor_shared_nothing -h 127.0.0.1 -p 6391 -c 2' &
sleep 3
echo "Testing connectivity..."
redis-cli -p 6391 ping
echo ""
echo "Testing cross-shard keys (should use message passing, not migration)..."
redis-cli -p 6391 set key_core0 "value0"
redis-cli -p 6391 set key_core1 "value1"
redis-cli -p 6391 get key_core0
redis-cli -p 6391 get key_core1
echo ""
echo "Running 2-core benchmark..."
redis-benchmark -p 6391 -c 20 -n 20000 -t set -q
pkill -f meteor_shared_nothing
sleep 1

echo ""
echo "🔧 Test 3: 4-core scaling test (target: linear scaling)"
echo "----------------------------------------------------"
timeout 12 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 ./meteor_shared_nothing -h 127.0.0.1 -p 6392 -c 4' &
sleep 4
echo "Testing 4-core connectivity..."
redis-cli -p 6392 ping
echo ""
echo "Testing multiple keys across shards..."
redis-cli -p 6392 set shard0_key "data0"
redis-cli -p 6392 set shard1_key "data1"  
redis-cli -p 6392 set shard2_key "data2"
redis-cli -p 6392 set shard3_key "data3"
echo ""
echo "Retrieving cross-shard data..."
redis-cli -p 6392 get shard0_key
redis-cli -p 6392 get shard1_key
redis-cli -p 6392 get shard2_key
redis-cli -p 6392 get shard3_key
echo ""
echo "Running 4-core benchmark (target: 400K+ RPS)..."
redis-benchmark -p 6392 -c 40 -n 40000 -t set -q
pkill -f meteor_shared_nothing
sleep 1

echo ""
echo "🔧 Test 4: Pipelined performance with multi-core"
echo "----------------------------------------------"
timeout 10 bash -c 'METEOR_USE_IO_URING=1 METEOR_USE_FIXED_BUFFERS=1 ./meteor_shared_nothing -h 127.0.0.1 -p 6393 -c 4' &
sleep 3
echo "Running pipelined benchmark (target: 1M+ RPS)..."
redis-benchmark -p 6393 -c 20 -n 20000 -t set -P 10 -q
pkill -f meteor_shared_nothing

echo ""
echo "✅ SHARED-NOTHING ARCHITECTURE TEST COMPLETE"
echo "============================================="
echo "📊 Expected Results:"
echo "   • No migration loop messages"
echo "   • Linear scaling with core count"
echo "   • 4-core: 400K+ RPS sustained"
echo "   • Pipelined: 1M+ RPS"
echo ""
echo "🎯 Key Improvements:"
echo "   • Connections stay on assigned cores"
echo "   • Commands routed via message passing"
echo "   • Eliminated connection bouncing"
echo "   • True shared-nothing architecture"