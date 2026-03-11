#!/bin/bash

echo "🚨 DIAGNOSING AND FIXING 100% CPU ISSUE"
echo "======================================="
echo "GCP Dashboard shows 100% CPU but VM shows low usage"
echo "Found stuck meteor process - investigating..."
echo

cd ~/meteor

echo "🔍 STEP 1: IDENTIFY THE PROBLEM"
echo "=============================="

echo "Current system load:"
uptime
echo

echo "Processes using CPU:"
ps aux --sort=-%cpu | head -10
echo

echo "Stuck processes found:"
pgrep -f meteor | while read pid; do
    echo "PID $pid: $(ps -p $pid -o pid,ppid,cmd,pcpu,pmem,time --no-headers)"
done
echo

echo "Processes on meteor ports:"
lsof -i :6379 2>/dev/null || echo "Port 6379: Clean"
lsof -i :6380 2>/dev/null || echo "Port 6380: Clean" 
lsof -i :6381 2>/dev/null || echo "Port 6381: Clean"
echo

echo "🧹 STEP 2: AGGRESSIVE CLEANUP"
echo "============================"

echo "Killing all meteor processes..."
pkill -9 -f meteor 2>/dev/null && echo "Meteor processes killed" || echo "No meteor processes found"

echo "Killing all memtier processes..."
pkill -9 -f memtier 2>/dev/null && echo "Memtier processes killed" || echo "No memtier processes found"

echo "Cleaning up all test ports..."
for port in 6379 6380 6381 6382; do
    sudo fuser -k ${port}/tcp 2>/dev/null && echo "Port $port cleaned" || echo "Port $port already free"
done

echo "Waiting for cleanup..."
sleep 5

echo "✅ STEP 3: VERIFY CLEANUP"
echo "======================="

echo "Remaining meteor processes:"
pgrep -f meteor || echo "✅ No meteor processes remaining"

echo "Port status after cleanup:"
ss -tlnp | grep -E ':6379|:6380|:6381' || echo "✅ All test ports are clean"

echo "System load after cleanup:"
uptime
echo

echo "🧪 STEP 4: CONTROLLED PERFORMANCE TEST"
echo "===================================="

echo "Starting Phase 5 with monitoring..."
echo "Launching server with 30-second timeout..."

# Start Phase 5 with explicit timeout and monitoring
timeout 30 ./meteor_phase5_step4a_simd_lockfree_monitoring -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l > /tmp/controlled_test.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"
echo "Waiting 8 seconds for initialization..."
sleep 8

# Check if server is running properly
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server process is alive"
    
    # Check if it's listening
    if ss -tlnp | grep :6379 > /dev/null; then
        echo "✅ Server is listening on port 6379"
        
        # Monitor CPU usage before benchmark
        echo "CPU usage before benchmark:"
        ps -p $SERVER_PID -o pid,pcpu,pmem,cmd --no-headers
        
        echo "Running controlled benchmark (5000 operations)..."
        timeout 20 memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 5000 --ratio=1:1 --pipeline=10 --key-pattern=R:R --key-minimum=1 --key-maximum=100000 > /tmp/controlled_bench.txt 2>&1 &
        BENCH_PID=$!
        
        # Monitor during benchmark
        echo "Monitoring CPU during benchmark..."
        for i in {1..10}; do
            echo "Second $i:"
            ps -p $SERVER_PID -o pid,pcpu,pmem --no-headers 2>/dev/null || echo "Server died"
            top -bn1 -p $SERVER_PID | grep $SERVER_PID || echo "Not in top"
            sleep 2
        done
        
        # Wait for benchmark to complete
        wait $BENCH_PID 2>/dev/null
        BENCH_EXIT=$?
        
        echo "Benchmark exit code: $BENCH_EXIT"
        
        if [ $BENCH_EXIT -eq 0 ]; then
            echo "✅ Benchmark completed successfully"
            echo
            echo "📊 RESULTS:"
            echo "=========="
            grep -A 3 -B 1 "Totals" /tmp/controlled_bench.txt || echo "No totals found"
            
            # Extract performance
            OPS_SEC=$(grep "Totals" /tmp/controlled_bench.txt 2>/dev/null | awk '{print $2}' | head -1)
            echo "Performance: ${OPS_SEC:-N/A} ops/sec"
            
        else
            echo "❌ Benchmark failed or timed out"
            echo "Benchmark output:"
            tail -10 /tmp/controlled_bench.txt
        fi
        
        echo
        echo "📈 Server statistics:"
        tail -10 /tmp/controlled_test.log | grep -E "(QPS|requests|ops|Total)"
        
    else
        echo "❌ Server not listening on port 6379"
        echo "Server log:"
        cat /tmp/controlled_test.log
    fi
else
    echo "❌ Server process died during initialization"
    echo "Server log:"
    cat /tmp/controlled_test.log
fi

# Clean up
echo "🧹 Final cleanup..."
kill $SERVER_PID 2>/dev/null || true
kill $BENCH_PID 2>/dev/null || true
sudo fuser -k 6379/tcp 2>/dev/null || true

echo
echo "🎯 DIAGNOSIS SUMMARY"
echo "=================="

echo "System status after controlled test:"
uptime
echo

echo "Any remaining high-CPU processes:"
ps aux --sort=-%cpu | head -5
echo

echo "GCP vs Local CPU discrepancy analysis:"
echo "- GCP Dashboard: 100% CPU (external monitoring)"
echo "- VM Internal: Low CPU usage (internal monitoring)"
echo "- Possible causes:"
echo "  1. Stuck processes consuming CPU cycles"
echo "  2. GCP monitoring lag or caching"
echo "  3. Hypervisor-level CPU accounting differences"
echo "  4. Background system processes not visible in user space"
echo

if [[ -n "$OPS_SEC" && "$OPS_SEC" != "N/A" ]]; then
    OPS_CLEAN=$(echo "$OPS_SEC" | tr -d ',')
    
    if (( $(echo "$OPS_CLEAN > 100000" | bc -l 2>/dev/null) )); then
        echo "🎉 EXCELLENT: Performance recovered after cleanup!"
        echo "   The stuck processes were causing the CPU bottleneck"
    elif (( $(echo "$OPS_CLEAN > 10000" | bc -l 2>/dev/null) )); then
        echo "✅ GOOD: Significant improvement after cleanup"
        echo "   Performance: ${OPS_CLEAN} ops/sec"
    elif (( $(echo "$OPS_CLEAN > 1000" | bc -l 2>/dev/null) )); then
        echo "⚠️  PARTIAL: Some improvement but still below target"
        echo "   Performance: ${OPS_CLEAN} ops/sec"
    else
        echo "❌ ISSUE: Performance still low despite cleanup"
        echo "   May indicate deeper system issues"
    fi
else
    echo "❌ INCOMPLETE: Could not measure performance"
fi

echo
echo "📋 RECOMMENDATIONS:"
echo "=================="
echo "1. Always kill stuck processes before testing"
echo "2. Use timeouts to prevent infinite loops"
echo "3. Monitor both GCP dashboard and internal metrics"
echo "4. Clean up ports between tests"
echo "5. Consider VM restart if issues persist"
echo
echo "Test completed at: $(date)"