#!/bin/bash

# **SEQUENTIAL BENCHMARK: Phase 1 Step 4 vs Phase 3 Step 3 vs Redis**
# Clean sequential testing with proper cleanup between each test

set -e

echo '🧪 SEQUENTIAL BENCHMARK COMPARISON'
echo '================================='
echo 'Phase 1 Step 4 (Port 6384) → Phase 3 Step 3 (Port 6383) → Redis (Port 6379)'
echo ''

# Cleanup function
cleanup_all() {
    echo '🧹 Cleaning up processes...'
    sudo pkill -f meteor || true
    sudo pkill -f redis-server || true
    sudo pkill -f redis-benchmark || true
    sudo fuser -k 6383/tcp 6384/tcp 6379/tcp 2>/dev/null || true
    sleep 3
}

# Test function
run_benchmark() {
    local server_name=$1
    local server_cmd=$2
    local port=$3
    local test_clients=$4
    local test_requests=$5
    
    echo "🚀 Testing $server_name on port $port"
    echo "  Command: $server_cmd"
    echo "  Clients: $test_clients, Requests: $test_requests"
    
    # Start server
    if [[ "$server_cmd" == *"redis-server"* ]]; then
        # Redis server
        $server_cmd &
        SERVER_PID=$!
        sleep 3
    else
        # Meteor server
        $server_cmd > /dev/null 2>&1 &
        SERVER_PID=$!
        sleep 5
    fi
    
    # Check if server started
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo "  ✅ Server started successfully (PID: $SERVER_PID)"
        
        # Run benchmark
        echo "  📈 Running benchmark..."
        RESULT=$(timeout 30 redis-benchmark -h 127.0.0.1 -p $port -c $test_clients -n $test_requests -d 64 -t set,get --csv -q 2>/dev/null | tail -2)
        
        if [ -n "$RESULT" ]; then
            SET_RPS=$(echo "$RESULT" | grep 'SET' | cut -d',' -f2 | tr -d '"' | sed 's/[^0-9.]//g')
            GET_RPS=$(echo "$RESULT" | grep 'GET' | cut -d',' -f2 | tr -d '"' | sed 's/[^0-9.]//g')
            
            echo "  ✅ Results: SET $SET_RPS ops/sec, GET $GET_RPS ops/sec"
            
            # Store results globally
            if [[ "$server_name" == *"Phase1"* ]]; then
                P1_SET=$SET_RPS
                P1_GET=$GET_RPS
            elif [[ "$server_name" == *"Phase3"* ]]; then
                P3_SET=$SET_RPS
                P3_GET=$GET_RPS
            elif [[ "$server_name" == *"Redis"* ]]; then
                REDIS_SET=$SET_RPS
                REDIS_GET=$GET_RPS
            fi
            
            # Save to results file
            echo "$server_name,$test_clients,$SET_RPS,$GET_RPS" >> benchmark_results.csv
        else
            echo "  ❌ Benchmark failed - no results"
            echo "$server_name,$test_clients,0,0" >> benchmark_results.csv
        fi
    else
        echo "  ❌ Server failed to start"
        echo "$server_name,$test_clients,0,0" >> benchmark_results.csv
    fi
    
    # Stop server
    echo "  🛑 Stopping server..."
    if [[ "$server_cmd" == *"redis-server"* ]]; then
        redis-cli -p $port shutdown 2>/dev/null || kill $SERVER_PID 2>/dev/null || true
    else
        kill $SERVER_PID 2>/dev/null || true
    fi
    
    # Wait for cleanup
    sleep 3
    echo "  ✅ Server stopped"
    echo ""
}

# Initialize
cleanup_all
echo 'Server,Clients,SET_RPS,GET_RPS' > benchmark_results.csv

# Test parameters
TEST_CLIENTS=100
TEST_REQUESTS=10000

# Initialize result variables
P1_SET=0
P1_GET=0
P3_SET=0
P3_GET=0
REDIS_SET=0
REDIS_GET=0

echo '📊 System Information:'
echo "  CPU: $(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)"
echo "  Cores: $(nproc)"
echo "  Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
echo "  Architecture: $(uname -m)"
echo ""

# Test 1: Phase 1 Step 4 on port 6384
echo '1️⃣  PHASE 1 STEP 4 TEST'
echo '====================='
if [ -f "./meteor_phase1_step4_epoll_io" ]; then
    run_benchmark "Phase1_Step4" "./meteor_phase1_step4_epoll_io -h 127.0.0.1 -p 6384 -m 128 -s 4" 6384 $TEST_CLIENTS $TEST_REQUESTS
else
    echo "❌ Phase 1 Step 4 binary not found!"
fi

cleanup_all

# Test 2: Phase 3 Step 3 on port 6383
echo '2️⃣  PHASE 3 STEP 3 TEST'
echo '====================='
if [ -f "./meteor_phase3_step3_batch_simd" ]; then
    run_benchmark "Phase3_Step3" "./meteor_phase3_step3_batch_simd -h 127.0.0.1 -p 6383 -m 128 -s 4" 6383 $TEST_CLIENTS $TEST_REQUESTS
else
    echo "❌ Phase 3 Step 3 binary not found!"
fi

cleanup_all

# Test 3: Redis on port 6379
echo '3️⃣  REDIS TEST'
echo '============='
run_benchmark "Redis" "redis-server --port 6379 --daemonize yes --save '' --appendonly no --bind 127.0.0.1" 6379 $TEST_CLIENTS $TEST_REQUESTS

cleanup_all

# Results Analysis
echo '📊 FINAL RESULTS COMPARISON'
echo '=========================='
echo ""
cat benchmark_results.csv
echo ""

echo '🎯 PERFORMANCE ANALYSIS:'
echo '======================='

# Create analysis script
python3 << 'PYTHON_EOF'
import csv

# Read results
results = {}
try:
    with open('benchmark_results.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            server = row['Server']
            set_rps = float(row['SET_RPS']) if row['SET_RPS'] != '0' else 0
            get_rps = float(row['GET_RPS']) if row['GET_RPS'] != '0' else 0
            results[server] = {'set': set_rps, 'get': get_rps}
except Exception as e:
    print(f"Error reading results: {e}")
    exit(1)

print("Raw Performance Data:")
print("-" * 40)
for server, data in results.items():
    print(f"{server:15s}: SET {data['set']:>8.0f}, GET {data['get']:>8.0f}")

print("\n🚀 PHASE 3 STEP 3 vs PHASE 1 STEP 4:")
print("-" * 45)

if 'Phase3_Step3' in results and 'Phase1_Step4' in results:
    p1_set = results['Phase1_Step4']['set']
    p1_get = results['Phase1_Step4']['get']
    p3_set = results['Phase3_Step3']['set']
    p3_get = results['Phase3_Step3']['get']
    
    if p1_set > 0 and p1_get > 0:
        set_improvement = ((p3_set - p1_set) / p1_set) * 100
        get_improvement = ((p3_get - p1_get) / p1_get) * 100
        
        print(f"SET: {p1_set:.0f} → {p3_set:.0f} ops/sec ({set_improvement:+.1f}%)")
        print(f"GET: {p1_get:.0f} → {p3_get:.0f} ops/sec ({get_improvement:+.1f}%)")
        
        avg_improvement = (set_improvement + get_improvement) / 2
        
        if avg_improvement > 10:
            print(f"✅ SIGNIFICANT IMPROVEMENT: {avg_improvement:.1f}% average")
        elif avg_improvement > 0:
            print(f"✅ IMPROVEMENT: {avg_improvement:.1f}% average")
        elif avg_improvement > -10:
            print(f"⚖️  COMPARABLE: {avg_improvement:+.1f}% average (within 10%)")
        else:
            print(f"⚠️  REGRESSION: {avg_improvement:.1f}% average")
    else:
        print("❌ Cannot compare - Phase 1 Step 4 failed")
else:
    print("❌ Missing data for comparison")

print("\n📈 COMPARISON WITH REDIS:")
print("-" * 30)

if 'Redis' in results:
    redis_set = results['Redis']['set']
    redis_get = results['Redis']['get']
    
    if 'Phase3_Step3' in results and redis_set > 0:
        p3_set = results['Phase3_Step3']['set']
        p3_get = results['Phase3_Step3']['get']
        
        set_ratio = (p3_set / redis_set) * 100 if redis_set > 0 else 0
        get_ratio = (p3_get / redis_get) * 100 if redis_get > 0 else 0
        
        print(f"Phase 3 Step 3 vs Redis:")
        print(f"  SET: {set_ratio:.1f}% of Redis performance")
        print(f"  GET: {get_ratio:.1f}% of Redis performance")
        
        if set_ratio > 80 and get_ratio > 80:
            print("✅ Excellent performance vs Redis!")
        elif set_ratio > 60 and get_ratio > 60:
            print("✅ Good performance vs Redis")
        else:
            print("📊 Development performance vs Redis")
    
    if 'Phase1_Step4' in results and redis_set > 0:
        p1_set = results['Phase1_Step4']['set']
        p1_get = results['Phase1_Step4']['get']
        
        set_ratio = (p1_set / redis_set) * 100 if redis_set > 0 else 0
        get_ratio = (p1_get / redis_get) * 100 if redis_get > 0 else 0
        
        print(f"\nPhase 1 Step 4 vs Redis:")
        print(f"  SET: {set_ratio:.1f}% of Redis performance")
        print(f"  GET: {get_ratio:.1f}% of Redis performance")

# Summary
print(f"\n🏆 BENCHMARK SUMMARY:")
print("=" * 25)
if results:
    best_set = max(results.values(), key=lambda x: x['set'])
    best_get = max(results.values(), key=lambda x: x['get'])
    
    best_set_server = [k for k, v in results.items() if v['set'] == best_set['set']][0]
    best_get_server = [k for k, v in results.items() if v['get'] == best_get['get']][0]
    
    print(f"Best SET performance: {best_set_server} ({best_set['set']:.0f} ops/sec)")
    print(f"Best GET performance: {best_get_server} ({best_get['get']:.0f} ops/sec)")
else:
    print("No valid results to analyze")

PYTHON_EOF

echo ""
echo "✅ Sequential benchmark completed!"
echo "📁 Results saved to benchmark_results.csv" 