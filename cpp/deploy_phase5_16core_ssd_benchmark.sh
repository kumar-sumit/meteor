#!/bin/bash

echo "🚀 PHASE 5 STEP 4A - FULL 16-CORE + SSD CACHE DEPLOYMENT & BENCHMARK"
echo "===================================================================="
echo "Target: mcache-ssd-tiering-poc VM (172.23.72.71)"
echo "Configuration: 16 cores, 16 shards, 2GB per shard (32GB total)"
echo "SSD Cache: /mnt/localDiskSSD (2.9TB RAID0)"
echo "Hardware: 16 cores, 125GB RAM, 8x NVMe SSD"
echo

echo "📂 STEP 1: Deploy 16-core SSD configuration to mcache VM"
echo "========================================================"
gcloud compute ssh --zone "asia-southeast1-a" "mcache-ssd-tiering-poc" --tunnel-through-iap --project "<your-gcp-project-id>" --command='
echo "🔧 Stopping any existing servers..."
pkill -f meteor || true
sleep 5

echo "🚀 Starting Phase 5 Step 4A - 16-CORE + SSD CONFIGURATION"
echo "========================================================="
echo "Configuration Details:"
echo "• CPU Cores: 16 (full VM utilization)"
echo "• Shards: 16 (1 shard per core)"
echo "• Memory per shard: 2GB"
echo "• Total memory: 32GB (25% of available 125GB)"
echo "• SSD Cache: /mnt/localDiskSSD"
echo "• Port: 6391"
echo

echo "Starting server with full configuration..."
nohup ~/meteor_phase5_mcache -h 0.0.0.0 -p 6391 -c 16 -s 16 -m 32768 -ssd /mnt/localDiskSSD -l > ~/phase5_16core_ssd.log 2>&1 &
SERVER_PID=$!

echo "Server started with PID: $SERVER_PID"
echo "Waiting 30 seconds for full initialization (16 cores + SSD)..."
sleep 30

echo "🔍 Checking server status..."
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server process running"
    
    if ss -tlnp | grep :6391; then
        echo "✅ Server listening on port 6391"
        
        echo
        echo "📊 SYSTEM STATUS AFTER STARTUP:"
        echo "==============================="
        echo "System load:"
        uptime
        echo
        echo "Memory usage:"
        free -h | grep Mem
        echo
        echo "SSD mount status:"
        df -h | grep localDiskSSD
        echo
        echo "Server process details:"
        ps aux | grep meteor_phase5_mcache | grep -v grep
        echo
        echo "✅ 16-CORE + SSD Phase 5 server ready for benchmarking!"
        
    else
        echo "❌ Server not listening on port 6391"
        echo "Server log (last 30 lines):"
        tail -30 ~/phase5_16core_ssd.log
    fi
else
    echo "❌ Server process died"
    echo "Server log (last 30 lines):"
    tail -30 ~/phase5_16core_ssd.log
fi
'

echo
echo "📊 STEP 2: Network benchmark from memtier-benchmarking VM"
echo "========================================================"
gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" --command='
echo "🚀 PHASE 5 STEP 4A - 16-CORE + SSD NETWORK BENCHMARK"
echo "===================================================="
echo "Target: 172.23.72.71:6391 (mcache-ssd-tiering-poc)"
echo "Configuration: 16 cores, 16 shards, 32GB memory, SSD cache"
echo "Previous 8-core results: redis-benchmark ~160K RPS, memtier ~41K RPS"
echo

echo "🔍 Testing connectivity..."
nc -zv 172.23.72.71 6391 && echo "✅ Connection successful" || echo "❌ Connection failed"

echo
echo "📊 REDIS-BENCHMARK TEST 1: Standard Load"
echo "========================================"
echo "Test: SET/GET, 100K requests, 50 clients"
redis-benchmark -h 172.23.72.71 -p 6391 -t set,get -n 100000 -c 50 -d 100 -q

echo
echo "📊 REDIS-BENCHMARK TEST 2: High Load"
echo "===================================="
echo "Test: SET/GET, 200K requests, 100 clients"
redis-benchmark -h 172.23.72.71 -p 6391 -t set,get -n 200000 -c 100 -d 100 -q

echo
echo "📊 REDIS-BENCHMARK TEST 3: Maximum Load"
echo "======================================="
echo "Test: SET/GET, 500K requests, 200 clients"
redis-benchmark -h 172.23.72.71 -p 6391 -t set,get -n 500000 -c 200 -d 100 -q

echo
echo "📊 MEMTIER_BENCHMARK TEST: Comparison"
echo "===================================="
echo "Test: 60 seconds, 100 connections"
memtier_benchmark --server=172.23.72.71 --port=6391 --ratio=1:1 -c 100 --test-time=60 --distinct-client-seed --randomize

echo
echo "📈 PERFORMANCE COMPARISON SUMMARY:"
echo "================================="
echo "PREVIOUS (8-core, 512MB memory, no SSD):"
echo "• redis-benchmark: 160K SET, 147-158K GET RPS"
echo "• memtier_benchmark: 41.2K RPS"
echo
echo "CURRENT (16-core, 32GB memory, SSD cache):"
echo "• redis-benchmark results: [See above]"
echo "• memtier_benchmark results: [See above]"
echo
echo "🎯 EXPECTED IMPROVEMENTS:"
echo "• 2x cores (8→16): Should improve throughput significantly"
echo "• 64x memory (512MB→32GB): Better caching, fewer evictions"
echo "• SSD cache: Hybrid memory+SSD storage for larger datasets"
echo "• Expected: 300K+ RPS with redis-benchmark"
'

echo
echo "✅ 16-CORE + SSD BENCHMARK DEPLOYMENT COMPLETED"
echo "=============================================="
echo "The script will:"
echo "1. Deploy Phase 5 with 16-core + SSD configuration"
echo "2. Run comprehensive network benchmarks"
echo "3. Compare with previous 8-core results"
echo "4. Demonstrate the performance impact of full hardware utilization"