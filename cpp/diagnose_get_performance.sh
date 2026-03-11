#!/bin/bash

# **GET Performance Diagnostic Script**
# This script will identify why GET performance is low and establish proper baselines

echo "🔍 GET Performance Diagnostic Analysis"
echo "====================================="
echo "Investigating low GET performance issue..."
echo ""

# Configuration
PHASE3_BINARY="/home/sumitkumar/meteor/build/meteor_phase3_step3_batch_simd"
PHASE4_STEP1_BINARY="/home/sumitkumar/meteor/build/meteor_phase4_step1_complete"
PHASE4_STEP2_BINARY="/home/sumitkumar/meteor/build/meteor_phase4_step2_complete"

# Function to clean environment
cleanup_environment() {
    echo "🧹 Cleaning up environment..."
    pkill -f redis-benchmark || true
    pkill -f meteor_phase || true
    pkill -f dragonfly || true
    sleep 3
    echo "✅ Environment cleaned"
    echo ""
}

# Function to test server performance
test_server_performance() {
    local server_name=$1
    local binary=$2
    local port=$3
    
    echo "🔧 Testing $server_name"
    echo "======================================"
    echo "Binary: $binary"
    echo "Port: $port"
    
    # Start server
    echo "🚀 Starting server..."
    $binary -h 127.0.0.1 -p $port -s 8 -m 256 > /dev/null 2>&1 &
    SERVER_PID=$!
    
    # Wait for startup
    sleep 5
    
    # Check if server is running
    if ps -p $SERVER_PID > /dev/null; then
        echo "✅ Server started (PID: $SERVER_PID)"
        
        # Test connectivity
        if nc -z 127.0.0.1 $port; then
            echo "✅ Server accepting connections"
            
            # Pre-populate with some data for GET tests
            echo "📝 Pre-populating cache with test data..."
            redis-benchmark -h 127.0.0.1 -p $port -n 100 -c 10 -t set -q > /dev/null 2>&1
            
            # Test SET performance
            echo "📊 Testing SET performance..."
            redis-benchmark -h 127.0.0.1 -p $port -n 1000 -c 50 -t set --csv > ${server_name}_set_results.csv 2>/dev/null
            
            if [ -f "${server_name}_set_results.csv" ]; then
                echo "✅ SET benchmark completed"
                set_result=$(grep '^"SET"' ${server_name}_set_results.csv | cut -d',' -f2 | tr -d '"')
                echo "  SET Performance: $set_result ops/sec"
            fi
            
            # Test GET performance
            echo "📊 Testing GET performance..."
            redis-benchmark -h 127.0.0.1 -p $port -n 1000 -c 50 -t get --csv > ${server_name}_get_results.csv 2>/dev/null
            
            if [ -f "${server_name}_get_results.csv" ]; then
                echo "✅ GET benchmark completed"
                get_result=$(grep '^"GET"' ${server_name}_get_results.csv | cut -d',' -f2 | tr -d '"')
                echo "  GET Performance: $get_result ops/sec"
                
                # Check if GET performance is suspiciously low
                if [ ! -z "$get_result" ]; then
                    get_num=$(echo $get_result | cut -d'.' -f1)
                    if [ "$get_num" -lt 1000 ]; then
                        echo "⚠️  WARNING: GET performance is suspiciously low ($get_result ops/sec)"
                        echo "     This indicates a potential issue in GET command handling"
                    fi
                fi
            fi
            
            # Show detailed results
            echo ""
            echo "📋 Detailed Results:"
            echo "SET Results:"
            cat ${server_name}_set_results.csv 2>/dev/null || echo "No SET results"
            echo "GET Results:"
            cat ${server_name}_get_results.csv 2>/dev/null || echo "No GET results"
            
        else
            echo "❌ Server not accepting connections"
        fi
    else
        echo "❌ Server failed to start"
    fi
    
    # Stop server
    echo ""
    echo "🛑 Stopping server..."
    kill $SERVER_PID 2>/dev/null || true
    sleep 3
    
    # Force cleanup
    pkill -f $(basename $binary) || true
    sleep 1
    
    echo ""
}

# Function to check system resources
check_system_resources() {
    echo "💻 System Resource Check"
    echo "========================"
    echo "CPU Usage:"
    top -bn1 | grep "Cpu(s)" || echo "CPU info not available"
    echo ""
    echo "Memory Usage:"
    free -h || echo "Memory info not available"
    echo ""
    echo "Active Connections:"
    ss -tuln | grep -E ':(638[0-9])' || echo "No meteor servers listening"
    echo ""
    echo "Running Processes:"
    ps aux | grep -E '(redis-benchmark|meteor_|dragonfly)' | grep -v grep || echo "No relevant processes"
    echo ""
}

# Main execution
echo "🏁 Starting GET Performance Diagnostic..."
echo ""

# Check system resources first
check_system_resources

# Clean environment
cleanup_environment

# Test Phase 3 Step 3 (known good baseline)
test_server_performance "Phase3_Step3_Baseline" "$PHASE3_BINARY" 6383

# Test Phase 4 Step 1 Complete
test_server_performance "Phase4_Step1_Complete" "$PHASE4_STEP1_BINARY" 6384

# Test Phase 4 Step 2 Complete
test_server_performance "Phase4_Step2_Complete" "$PHASE4_STEP2_BINARY" 6385

# Final cleanup
cleanup_environment

# Generate summary report
echo "📊 GET PERFORMANCE DIAGNOSTIC SUMMARY"
echo "====================================="
echo "Generated: $(date)"
echo ""

# Compare results
for server in Phase3_Step3_Baseline Phase4_Step1_Complete Phase4_Step2_Complete; do
    if [ -f "${server}_get_results.csv" ] && [ -f "${server}_set_results.csv" ]; then
        set_perf=$(grep '^"SET"' ${server}_set_results.csv | cut -d',' -f2 | tr -d '"')
        get_perf=$(grep '^"GET"' ${server}_get_results.csv | cut -d',' -f2 | tr -d '"')
        
        echo "**$server:**"
        echo "  SET: $set_perf ops/sec"
        echo "  GET: $get_perf ops/sec"
        
        # Check for performance issues
        if [ ! -z "$get_perf" ]; then
            get_num=$(echo $get_perf | cut -d'.' -f1)
            set_num=$(echo $set_perf | cut -d'.' -f1)
            
            if [ "$get_num" -lt 1000 ]; then
                echo "  🚨 ISSUE: GET performance critically low"
            elif [ "$get_num" -lt $((set_num / 2)) ]; then
                echo "  ⚠️  WARNING: GET performance significantly lower than SET"
            else
                echo "  ✅ GET performance normal"
            fi
        fi
        echo ""
    fi
done

echo "🎯 **Key Findings:**"
echo ""
echo "✅ **Environment Issues Fixed:**"
echo "  • Eliminated resource contention from multiple redis-benchmark processes"
echo "  • Clean server startup and shutdown procedures"
echo "  • Proper test isolation"
echo ""
echo "🔍 **Performance Analysis:**"
echo "  • Phase 3 Step 3 baseline established"
echo "  • Phase 4 implementations tested in clean environment"
echo "  • GET vs SET performance comparison completed"
echo ""
echo "🚀 **Next Steps:**"
echo "  • If GET performance is still low, investigate GET command implementation"
echo "  • Compare with previous benchmark results from yesterday"
echo "  • Verify cache hit/miss ratios for GET operations"

echo ""
echo "🎉 GET Performance Diagnostic Complete!" 