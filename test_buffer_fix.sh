#!/bin/bash

echo "=== TESTING BUFFER CORRUPTION FIX ==="

# Test comprehensive functionality including memtier pipeline=1
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" -- '
cd /mnt/externalDisk/meteor &&

echo "=== 1. Kill any existing servers ===" &&
pkill -f meteor 2>/dev/null || true &&
sleep 2 &&

echo "=== 2. Starting buffer-fixed server ===" &&
nohup ./meteor_final_buffer_fix -c 4 -s 4 > buffer_fix_test.log 2>&1 & 
SERVER_PID=$! &&
sleep 3 &&

echo "=== 3. Basic functionality test ===" &&
echo -e "PING\r" | nc 127.0.0.1 6379 &&
echo -e "SET test_key test_value\r" | nc 127.0.0.1 6379 &&
echo -e "GET test_key\r" | nc 127.0.0.1 6379 &&
echo -e "SETEX ttl_key 5 ttl_value\r" | nc 127.0.0.1 6379 &&
echo -e "GET ttl_key\r" | nc 127.0.0.1 6379 &&

echo "=== 4. CRITICAL: memtier pipeline=1 test ===" &&
echo "Running memtier with pipeline=1 (problematic case)..." &&
memtier_benchmark -s 127.0.0.1 -p 6379 --pipeline=1 --clients=2 --requests=100 --data-size=32 --test-time=10 2>&1 | head -20 &&

echo "=== 5. memtier pipeline=20 test (should work) ===" &&
memtier_benchmark -s 127.0.0.1 -p 6379 --pipeline=20 --clients=2 --requests=100 --data-size=32 --test-time=10 2>&1 | head -20 &&

echo "=== 6. Cleanup ===" &&
kill $SERVER_PID 2>/dev/null || true &&
echo "Test completed!"
'












