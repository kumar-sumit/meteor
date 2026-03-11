#!/bin/bash

# **UBUNTU 22 vs 24 PERFORMANCE COMPARISON TOOL**
# Comprehensive benchmarking to quantify performance differences
# and identify the root cause of performance regression

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1"; }
highlight() { echo -e "${CYAN}$1${NC}"; }

# Configuration
RESULTS_DIR="performance_comparison_$(date +%Y%m%d_%H%M%S)"
UBUNTU22_BINARY="${1:-meteor-server-ubuntu22}"
UBUNTU24_BINARY="${2:-meteor-server-ubuntu24-optimized}"
BASE_PORT=6380
TEST_DURATION=30
WARMUP_TIME=10

print_banner() {
    cat << 'BANNER'
╔═══════════════════════════════════════════════════════════╗
║        📊 UBUNTU 22 vs 24 PERFORMANCE COMPARISON        ║
║              Comprehensive QPS Analysis                  ║
╚═══════════════════════════════════════════════════════════╝
BANNER
}

# Setup test environment
setup_test_env() {
    log "Setting up test environment..."
    
    mkdir -p "$RESULTS_DIR"
    cd "$RESULTS_DIR"
    
    # Clean up any existing processes
    pkill -f meteor-server || true
    pkill -f meteor || true
    sleep 3
    
    # Create test configuration
    cat > test_config.conf << CONFIG
# Test Configuration
cores = 4
shards = 4
max-memory = 4096mb
bind = 127.0.0.1
port = $BASE_PORT
pipeline-enabled = true
work-stealing = true
numa-aware = true
cpu-affinity = true
CONFIG
    
    log "Test environment ready: $RESULTS_DIR"
}

# System performance baseline
measure_system_baseline() {
    highlight "📋 SYSTEM PERFORMANCE BASELINE"
    
    log "Measuring system performance baseline..."
    
    # CPU performance
    echo "CPU Performance Test:" > system_baseline.txt
    sysbench cpu --cpu-max-prime=10000 --threads=4 run >> system_baseline.txt 2>&1
    
    # Memory performance
    echo -e "\nMemory Performance Test:" >> system_baseline.txt
    sysbench memory --memory-total-size=1G --threads=4 run >> system_baseline.txt 2>&1
    
    # I/O performance (if available)
    if [ -w /tmp ]; then
        echo -e "\nI/O Performance Test:" >> system_baseline.txt
        sysbench fileio --file-total-size=1G --file-test-mode=seqwr prepare > /dev/null 2>&1
        sysbench fileio --file-total-size=1G --file-test-mode=seqwr --threads=4 run >> system_baseline.txt 2>&1
        sysbench fileio cleanup > /dev/null 2>&1
    fi
    
    log "System baseline measured"
}

# Start server with monitoring
start_server_with_monitoring() {
    local binary="$1"
    local port="$2"
    local config="$3"
    local log_prefix="$4"
    
    if [ ! -f "../$binary" ]; then
        error "Binary not found: ../$binary"
        return 1
    fi
    
    log "Starting server: $binary on port $port"
    
    # Start server with resource monitoring
    timeout 300 ../bin/time -v ../"$binary" \
        --config="$config" \
        --port="$port" \
        --cores=4 \
        --shards=4 \
        > "${log_prefix}_server.log" 2>&1 &
    
    local server_pid=$!
    echo $server_pid > "${log_prefix}_server.pid"
    
    # Wait for server to start
    local attempts=0
    while [ $attempts -lt 30 ]; do
        if redis-cli -h 127.0.0.1 -p "$port" ping > /dev/null 2>&1; then
            log "Server started successfully (PID: $server_pid)"
            return 0
        fi
        sleep 1
        ((attempts++))
    done
    
    error "Server failed to start within 30 seconds"
    return 1
}

# Stop server
stop_server() {
    local log_prefix="$1"
    
    if [ -f "${log_prefix}_server.pid" ]; then
        local pid=$(cat "${log_prefix}_server.pid")
        log "Stopping server (PID: $pid)"
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
        rm -f "${log_prefix}_server.pid"
    fi
}

# Comprehensive benchmark suite
run_benchmark_suite() {
    local binary="$1"
    local port="$2"
    local results_prefix="$3"
    
    highlight "🚀 RUNNING BENCHMARK SUITE: $binary"
    
    # Start server
    start_server_with_monitoring "$binary" "$port" "test_config.conf" "$results_prefix" || return 1
    
    # Warmup
    log "Warming up server..."
    timeout 30 redis-benchmark -h 127.0.0.1 -p "$port" -t ping -c 10 -n 1000 > /dev/null 2>&1 || true
    sleep "$WARMUP_TIME"
    
    # Test configurations
    declare -A test_configs=(
        ["connectivity"]="1 1 10000 baseline_connectivity"
        ["light_load"]="10 2 50000 light_workload"
        ["standard_load"]="20 4 100000 standard_workload"  
        ["pipeline_10"]="30 8 150000 pipeline_depth_10"
        ["pipeline_20"]="50 8 200000 pipeline_depth_20"
        ["high_concurrency"]="100 16 300000 stress_test"
    )
    
    for test_name in connectivity light_load standard_load pipeline_10 pipeline_20 high_concurrency; do
        local config=${test_configs[$test_name]}
        local clients=$(echo $config | cut -d' ' -f1)
        local threads=$(echo $config | cut -d' ' -f2)
        local requests=$(echo $config | cut -d' ' -f3)
        local description=$(echo $config | cut -d' ' -f4)
        
        log "Running test: $test_name ($description)"
        
        # Redis-benchmark test
        local output_file="${results_prefix}_${test_name}_redis_benchmark.txt"
        timeout 120 redis-benchmark \
            -h 127.0.0.1 -p "$port" \
            -c "$clients" \
            -n "$requests" \
            -t get,set \
            -P $([ "$test_name" == "pipeline_10" ] && echo 10 || [ "$test_name" == "pipeline_20" ] && echo 20 || echo 1) \
            --csv > "$output_file" 2>&1 || warn "redis-benchmark failed for $test_name"
        
        # Memtier benchmark test (if available)
        if command -v memtier_benchmark > /dev/null; then
            local memtier_output="${results_prefix}_${test_name}_memtier.txt"
            local pipeline_depth=$([ "$test_name" == "pipeline_10" ] && echo 10 || [ "$test_name" == "pipeline_20" ] && echo 20 || echo 1)
            
            timeout 120 memtier_benchmark \
                --server=127.0.0.1 --port="$port" \
                --clients="$clients" --threads="$threads" \
                --requests="$requests" \
                --pipeline="$pipeline_depth" \
                --test-time="$TEST_DURATION" \
                --ratio=1:1 --data-size=64 \
                --key-pattern=R:R \
                --hide-histogram > "$memtier_output" 2>&1 || warn "memtier_benchmark failed for $test_name"
        fi
        
        sleep 5  # Brief pause between tests
    done
    
    # Resource usage snapshot
    if [ -f "${results_prefix}_server.pid" ]; then
        local pid=$(cat "${results_prefix}_server.pid")
        ps -p "$pid" -o pid,ppid,pcpu,pmem,vsz,rss,etime,comm > "${results_prefix}_resource_usage.txt" 2>/dev/null || true
    fi
    
    # Stop server
    stop_server "$results_prefix"
    
    log "Benchmark suite completed for $binary"
}

# Analyze results
analyze_results() {
    highlight "📊 ANALYZING PERFORMANCE RESULTS"
    
    log "Processing benchmark results..."
    
    # Create analysis report
    cat > performance_analysis.md << ANALYSIS
# Performance Comparison Analysis

## Test Environment
- Date: $(date)
- Ubuntu Version: $(lsb_release -d | cut -f2)
- Kernel: $(uname -r)
- CPU: $(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//')
- Memory: $(free -h | grep Mem | awk '{print $2}')

## Binaries Tested
- Ubuntu 22 Binary: $UBUNTU22_BINARY
- Ubuntu 24 Binary: $UBUNTU24_BINARY

## Results Summary

ANALYSIS

    # Process results for each binary
    for binary_prefix in ubuntu22 ubuntu24; do
        echo "### ${binary_prefix^} Results" >> performance_analysis.md
        echo "" >> performance_analysis.md
        
        # Extract QPS from memtier results
        for test in connectivity light_load standard_load pipeline_10 pipeline_20 high_concurrency; do
            local memtier_file="${binary_prefix}_${test}_memtier.txt"
            if [ -f "$memtier_file" ]; then
                local qps=$(grep "Totals" "$memtier_file" | awk '{print $2}' | head -1)
                local latency=$(grep "Totals" "$memtier_file" | awk '{print $5}' | head -1)
                echo "- **$test**: ${qps:-N/A} QPS, ${latency:-N/A}ms latency" >> performance_analysis.md
            fi
        done
        echo "" >> performance_analysis.md
    done
    
    # Generate comparison
    echo "## Performance Comparison" >> performance_analysis.md
    echo "" >> performance_analysis.md
    
    # Calculate performance differences
    for test in connectivity light_load standard_load pipeline_10 pipeline_20 high_concurrency; do
        local ubuntu22_file="ubuntu22_${test}_memtier.txt"
        local ubuntu24_file="ubuntu24_${test}_memtier.txt"
        
        if [ -f "$ubuntu22_file" ] && [ -f "$ubuntu24_file" ]; then
            local qps22=$(grep "Totals" "$ubuntu22_file" | awk '{print $2}' | sed 's/,//g' | head -1)
            local qps24=$(grep "Totals" "$ubuntu24_file" | awk '{print $2}' | sed 's/,//g' | head -1)
            
            if [ -n "$qps22" ] && [ -n "$qps24" ]; then
                local diff=$(echo "scale=2; ($qps24 - $qps22) / $qps22 * 100" | bc -l 2>/dev/null || echo "calc_error")
                echo "- **$test**: ${diff}% difference (Ubuntu 24 vs Ubuntu 22)" >> performance_analysis.md
            fi
        fi
    done
    
    log "Analysis complete: performance_analysis.md"
}

# Generate recommendations
generate_recommendations() {
    highlight "💡 GENERATING OPTIMIZATION RECOMMENDATIONS"
    
    cat >> performance_analysis.md << RECOMMENDATIONS

## Optimization Recommendations

Based on the performance analysis, here are the recommendations:

### If Ubuntu 24 is significantly slower:
1. **Compiler Optimization**: Rebuild with GCC 11 (Ubuntu 22 default) instead of GCC 13
2. **Library Downgrade**: Use Ubuntu 22 library versions in containers
3. **Memory Allocator**: Force jemalloc usage: \`LD_PRELOAD=libjemalloc.so.2\`
4. **CPU Settings**: Lock CPU frequency to maximum performance mode
5. **Kernel Parameters**: Tune scheduler and memory management settings

### If performance is similar:
1. **Configuration Issue**: Check server parameters (cores, shards, memory)
2. **System Resources**: Verify NUMA topology and CPU affinity
3. **Network Stack**: Optimize network buffer sizes and TCP settings

### If Ubuntu 24 is faster:
1. **Adopt Ubuntu 24**: The newer libraries and compiler optimizations are working
2. **Further Optimize**: Leverage GCC 13 specific optimizations
3. **Update Dependencies**: Ensure all libraries are using latest versions

### Immediate Actions:
\`\`\`bash
# Test with different memory allocators
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 ./meteor-server

# Lock CPU frequency
sudo cpupower frequency-set -g performance

# NUMA optimization
numactl --cpunodebind=0 --membind=0 ./meteor-server

# Rebuild with specific compiler
g++-11 -O3 -march=native -mtune=native ... (use Ubuntu 22 flags)
\`\`\`

RECOMMENDATIONS

    log "Recommendations generated"
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    pkill -f meteor-server || true
    pkill -f redis-benchmark || true
    pkill -f memtier_benchmark || true
}

# Main execution
main() {
    print_banner
    echo ""
    
    # Validate binaries
    if [ ! -f "$UBUNTU22_BINARY" ]; then
        error "Ubuntu 22 binary not found: $UBUNTU22_BINARY"
        echo "Usage: $0 <ubuntu22-binary> <ubuntu24-binary>"
        exit 1
    fi
    
    if [ ! -f "$UBUNTU24_BINARY" ]; then
        error "Ubuntu 24 binary not found: $UBUNTU24_BINARY"
        echo "Usage: $0 <ubuntu22-binary> <ubuntu24-binary>"
        exit 1
    fi
    
    # Set cleanup trap
    trap cleanup EXIT
    
    setup_test_env
    
    # Install sysbench if not available
    if ! command -v sysbench > /dev/null; then
        warn "sysbench not found, installing..."
        sudo apt install -y sysbench || warn "Could not install sysbench"
    fi
    
    measure_system_baseline
    
    # Test Ubuntu 22 binary
    run_benchmark_suite "$UBUNTU22_BINARY" $((BASE_PORT + 1)) "ubuntu22"
    
    # Test Ubuntu 24 binary  
    run_benchmark_suite "$UBUNTU24_BINARY" $((BASE_PORT + 2)) "ubuntu24"
    
    analyze_results
    generate_recommendations
    
    highlight "🎊 PERFORMANCE COMPARISON COMPLETE"
    echo "=================================="
    echo "Results directory: $RESULTS_DIR"
    echo "Analysis report: $RESULTS_DIR/performance_analysis.md"
    echo ""
    
    # Show quick summary
    if [ -f performance_analysis.md ]; then
        echo "Quick Summary:"
        grep -E "^\- \*\*.*\*\*:" performance_analysis.md | head -10 || echo "See detailed report"
    fi
}

# Handle help
if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
    echo "Usage: $0 <ubuntu22-binary> <ubuntu24-binary>"
    echo ""
    echo "This script performs comprehensive performance comparison between"
    echo "Ubuntu 22 and Ubuntu 24 builds of the Meteor server."
    echo ""
    echo "Example:"
    echo "  $0 meteor-server-old meteor-server-ubuntu24-optimized"
    exit 0
fi

main "$@"










