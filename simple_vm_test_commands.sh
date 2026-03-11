#!/bin/bash
# 🧪 SIMPLE VM TEST COMMANDS - Copy/paste these blocks sequentially

echo "===== BLOCK 1: SSH TO VM ====="
echo "gcloud compute ssh --zone \"asia-southeast1-a\" \"memtier-benchmarking\" \\"
echo "  --tunnel-through-iap --project \"<your-gcp-project-id>\""
echo ""

echo "===== BLOCK 2: BUILD REDIS-STYLE VERSION ====="
echo "cd /mnt/externalDisk/meteor"
echo "export TMPDIR=/dev/shm"
echo "pkill -f meteor 2>/dev/null || true"
echo "sleep 3"
echo ""
echo "g++ -std=c++17 -O3 -DHAS_LINUX_EPOLL -march=native -mavx2 -mavx -msse4.2 \\"
echo "  -pthread -o meteor_redis_style meteor_commercial_lru_ttl_redis_style.cpp -luring"
echo ""
echo "ls -la meteor_redis_style"
echo ""

echo "===== BLOCK 3: START SERVER ====="
echo "./meteor_redis_style -h 127.0.0.1 -p 6379 -c 12 -s 4 -m 2048 &"
echo "SERVER_PID=\$!"
echo "sleep 5"
echo "redis-cli -p 6379 ping"
echo ""

echo "===== BLOCK 4: CRITICAL TTL TESTS ====="
echo "redis-cli -p 6379 flushall"
echo ""
echo "# Test 1: Key without TTL (should return -1, not -2)"
echo "redis-cli -p 6379 set test1 \"no ttl\""
echo "redis-cli -p 6379 ttl test1"
echo "echo \"Expected: -1\""
echo ""
echo "# Test 2: Non-existent key (should return -2)"  
echo "redis-cli -p 6379 ttl nonexistent_key"
echo "echo \"Expected: -2\""
echo ""
echo "# Test 3: Key with TTL (should return >0)"
echo "redis-cli -p 6379 set test3 \"has ttl\" EX 60"
echo "redis-cli -p 6379 ttl test3"
echo "echo \"Expected: >0 and ≤60\""
echo ""
echo "# Test 4: EXPIRE command"
echo "redis-cli -p 6379 set test4 \"gets expire\""
echo "redis-cli -p 6379 expire test4 45"
echo "redis-cli -p 6379 ttl test4"
echo "echo \"Expected: 1, then >0 and ≤45\""
echo ""

echo "===== BLOCK 5: PERFORMANCE BENCHMARK ====="
echo "memtier_benchmark --server=127.0.0.1 --port=6379 --protocol=redis \\"
echo "  --clients=50 --threads=12 --pipeline=10 --data-size=64 \\"
echo "  --key-pattern=R:R --ratio=1:3 --test-time=30"
echo ""
echo "# Look for 'Requests/sec' in output - should be 5M+"
echo ""

echo "===== BLOCK 6: CLEANUP ====="
echo "kill \$SERVER_PID 2>/dev/null"
echo ""

echo "🎯 SUCCESS CRITERIA:"
echo "✅ TTL returns -1 for keys without TTL (not -2)"
echo "✅ TTL commands respond quickly (no hanging)"  
echo "✅ Benchmark shows 5M+ QPS (no performance regression)"
echo "✅ Server stable throughout testing"













