#!/bin/bash
# 🧪 QUICK ROUTING CONSISTENCY TEST

echo "===== STEP 1: SSH TO VM ====="
echo "gcloud compute ssh --zone \"asia-southeast1-a\" \"memtier-benchmarking\" \\"
echo "  --tunnel-through-iap --project \"<your-gcp-project-id>\""
echo ""

echo "===== STEP 2: BUILD ROUTING FIX VERSION ====="
echo "cd /mnt/externalDisk/meteor"
echo "export TMPDIR=/dev/shm"
echo "pkill -f meteor 2>/dev/null || true && sleep 3"
echo ""
echo "g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \\"
echo "  -pthread -o meteor_routing_consistent meteor_commercial_lru_ttl_routing_consistent.cpp -luring"
echo ""

echo "===== STEP 3: START SERVER ====="
echo "./meteor_routing_consistent -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &"
echo "SERVER_PID=\$!"
echo "sleep 5"
echo "redis-cli -p 6379 ping"
echo ""

echo "===== STEP 4: ROUTING CONSISTENCY TEST ====="
echo "redis-cli -p 6379 flushall"
echo ""
echo "# This was the EXACT issue - random -2/-1 results"
echo "echo '🎯 Testing 10 keys for consistent routing'"
echo "for i in {1..10}; do"
echo "    KEY=\"test_key_\\\$i\""
echo "    redis-cli -p 6379 set \"\\\$KEY\" \"value_\\\$i\""
echo "    TTL_RESULT=\\\$(redis-cli -p 6379 ttl \"\\\$KEY\")"
echo "    echo \"Key \\\$i: TTL -> \\\$TTL_RESULT (should always be -1)\""
echo "done"
echo ""
echo "echo '✅ SUCCESS: All -1 results = routing consistent'"
echo "echo '❌ FAILURE: Mixed -2/-1 results = routing still broken'"
echo ""

echo "===== STEP 5: VERIFY TTL WITH TTL KEYS ====="
echo "redis-cli -p 6379 set ttl_key \"expires\" EX 60"
echo "for i in {1..5}; do"
echo "    TTL_RESULT=\\\$(redis-cli -p 6379 ttl ttl_key)"
echo "    echo \"TTL check \\\$i: \\\$TTL_RESULT (should always be >0)\""
echo "done"
echo ""

echo "===== STEP 6: CLEANUP ====="
echo "kill \$SERVER_PID 2>/dev/null"
echo ""

echo "🎯 WHAT TO LOOK FOR:"
echo "✅ All keys without TTL return -1 (consistently)"  
echo "✅ All keys with TTL return >0 (consistently)"
echo "✅ No random -2 results for existing keys"
echo "❌ If you still see mixed results, routing fix incomplete"













