#!/bin/bash

echo "🎯 MEMTIER TESTS OPTIMIZED FOR HIGH CACHE HIT RATES"
echo "=============================================="

# Test comprehensive cache hit optimization
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" -- '
cd /dev/shm &&

echo "=== 1. VERIFYING SERVER IS RUNNING ===" &&
ps aux | grep meteor_buffer_fix_shm | grep -v grep || echo "Starting server..." &&
pkill -f meteor_buffer_fix_shm || true &&
sleep 2 &&
nohup ./meteor_buffer_fix_shm -c 4 -s 4 > server.log 2>&1 & 
SERVER_PID=$! &&
sleep 3 &&

echo "=== 2. SMALL KEY SPACE TEST (High Hit Rate Expected) ===" &&
echo "Key space: 100 keys, 1000 requests, Gaussian distribution" &&
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --key-minimum=1 --key-maximum=100 \
  --key-pattern=G:G \
  --requests=1000 \
  --clients=1 --threads=1 \
  --pipeline=1 \
  --ratio=1:9 \
  --data-size=64 &&

echo -e "\n=== 3. MEDIUM KEY SPACE TEST (Good Hit Rate Expected) ===" &&
echo "Key space: 1000 keys, 5000 requests, Sequential pattern" &&
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --key-minimum=1 --key-maximum=1000 \
  --key-pattern=S:S \
  --requests=5000 \
  --clients=1 --threads=1 \
  --pipeline=1 \
  --ratio=1:9 \
  --data-size=64 &&

echo -e "\n=== 4. WARMUP + HIGH LOCALITY TEST ===" &&
echo "Step 1: Warmup with 2000 SETs to populate cache" &&
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --key-minimum=1 --key-maximum=2000 \
  --key-pattern=S:S \
  --requests=2000 \
  --clients=1 --threads=1 \
  --pipeline=1 \
  --ratio=10:0 \
  --data-size=64 &&

echo "Step 2: High-locality GETs on warmed cache" &&
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --key-minimum=1 --key-maximum=2000 \
  --key-pattern=G:G \
  --requests=5000 \
  --clients=1 --threads=1 \
  --pipeline=1 \
  --ratio=0:10 \
  --data-size=64 &&

echo -e "\n=== 5. PIPELINED HIGH HIT RATE TEST ===" &&
echo "Pipeline=10 with small key space for comparison" &&
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --key-minimum=1 --key-maximum=500 \
  --key-pattern=G:G \
  --requests=2000 \
  --clients=1 --threads=1 \
  --pipeline=10 \
  --ratio=1:9 \
  --data-size=64 &&

echo -e "\n=== 6. TTL CACHE HIT RATE TEST ===" &&
echo "Test cache hits with TTL keys (SETEX commands)" &&
echo "Populating with SETEX commands..." &&
for i in {1..100}; do
  redis-cli SETEX "ttl_key_$i" 300 "value_$i" > /dev/null
done &&
echo "Testing GET hit rate on TTL keys..." &&
memtier_benchmark -s 127.0.0.1 -p 6379 \
  --key-prefix="ttl_key_" \
  --key-minimum=1 --key-maximum=100 \
  --requests=500 \
  --clients=1 --threads=1 \
  --pipeline=1 \
  --ratio=0:10 \
  --data-size=64 &&

echo -e "\n=== TEST COMPLETED ===" &&
kill $SERVER_PID 2>/dev/null || true
'












