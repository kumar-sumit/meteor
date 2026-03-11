#!/bin/bash

# **UBUNTU 24 PERFORMANCE REBUILD SCRIPT**
# Rebuild Meteor server with Ubuntu 24 optimized libraries while maintaining Ubuntu 22 performance
# This script addresses common performance regressions when moving from Ubuntu 22 to 24

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

print_banner() {
    cat << 'BANNER'
╔═══════════════════════════════════════════════════════════╗
║       🚀 UBUNTU 24 PERFORMANCE REBUILD OPTIMIZER        ║
║          Maintain Ubuntu 22 Performance on Ubuntu 24    ║
╚═══════════════════════════════════════════════════════════╝
BANNER
}

# Configuration
SOURCE_FILES=(
    "cpp/sharded_server_phase8_step25_zero_overhead_temporal_coherence.cpp"
    "meteor_phase1_2b_syscall_reduction_single_command_fixed.cpp"
    "cpp/sharded_server_performance_v2_fixed.cpp"
    "meteor_avx512_optimized.cpp"
)
OUTPUT_BINARY="meteor-server-ubuntu24-optimized"
BUILD_LOG="ubuntu24_rebuild.log"

# Detect system configuration
detect_system() {
    log "Detecting system configuration..."
    
    # Ubuntu version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        UBUNTU_VERSION=$VERSION_ID
    else
        error "Cannot detect Ubuntu version"
        exit 1
    fi
    
    # CPU architecture
    ARCH=$(uname -m)
    CORES=$(nproc)
    
    # CPU model for optimization
    CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name:[ ]*//')
    
    log "System: Ubuntu $UBUNTU_VERSION, $ARCH, $CORES cores"
    info "CPU: $CPU_MODEL"
}

# Install Ubuntu 24 optimized dependencies
install_dependencies() {
    highlight "📦 INSTALLING UBUNTU 24 OPTIMIZED DEPENDENCIES"
    
    log "Updating package lists..."
    sudo apt update
    
    # Core development tools with specific versions for performance
    log "Installing core development tools..."
    sudo apt install -y \
        build-essential \
        g++-13 \
        clang-18 \
        cmake \
        pkg-config \
        git
    
    # Performance-critical libraries
    log "Installing performance libraries..."
    sudo apt install -y \
        libboost-all-dev \
        libboost-fiber-dev \
        libboost-context-dev \
        libboost-system-dev \
        liburing-dev \
        libnuma-dev \
        libjemalloc-dev \
        libtcmalloc-minimal4
    
    # Additional optimization tools
    log "Installing optimization tools..."
    sudo apt install -y \
        cpupower-tools \
        numactl \
        perf-tools-unstable \
        valgrind
    
    log "Dependencies installed successfully"
}

# Configure system for optimal performance
configure_system() {
    highlight "⚙️ CONFIGURING SYSTEM FOR OPTIMAL PERFORMANCE"
    
    # CPU frequency scaling
    log "Setting CPU frequency scaling to performance mode..."
    sudo cpupower frequency-set -g performance 2>/dev/null || warn "Could not set CPU frequency scaling"
    
    # Kernel parameters
    log "Optimizing kernel parameters..."
    
    # Create temporary sysctl configuration
    sudo tee /etc/sysctl.d/99-meteor-ubuntu24.conf > /dev/null << SYSCTL
# Meteor Ubuntu 24 Performance Optimizations
# Network performance
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 65535

# Memory management
vm.overcommit_memory = 1
vm.swappiness = 1
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5

# File descriptor limits
fs.file-max = 2097152

# Scheduler optimizations
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 0
SYSCTL
    
    sudo sysctl -p /etc/sysctl.d/99-meteor-ubuntu24.conf
    
    # Disable transparent huge pages (can cause latency spikes)
    log "Configuring memory management..."
    echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null || warn "Could not disable THP"
    
    log "System configuration complete"
}

# Determine optimal compiler flags for Ubuntu 24
get_compiler_flags() {
    local compiler="$1"
    
    # Base optimization flags
    local base_flags="-std=c++20 -O3 -DNDEBUG -march=native -mtune=native"
    
    # Ubuntu 24 specific optimizations
    local ubuntu24_flags="-flto -ffast-math -funroll-loops -finline-functions"
    ubuntu24_flags="$ubuntu24_flags -fomit-frame-pointer -falign-functions=16"
    
    # Architecture specific flags
    if [[ "$ARCH" == "x86_64" ]]; then
        local arch_flags="-mavx2 -mavx512f -mavx512dq -mavx512bw -mavx512vl -mavx512cd"
        arch_flags="$arch_flags -msse4.2 -mfma -mpopcnt -mbmi2 -mlzcnt"
    elif [[ "$ARCH" == "aarch64" ]]; then
        local arch_flags="-mcpu=native"
    else
        local arch_flags=""
    fi
    
    # Compiler specific optimizations
    if [[ "$compiler" == "g++" ]]; then
        # GCC 13 specific optimizations for Ubuntu 24
        local compiler_flags="-finline-small-functions -findirect-inlining"
        compiler_flags="$compiler_flags -fdevirtualize -fdevirtualize-speculatively"
        compiler_flags="$compiler_flags -fstrict-aliasing -fno-plt"
        
        # GCC 13 has better loop optimizations
        compiler_flags="$compiler_flags -ftree-loop-distribute-patterns"
        compiler_flags="$compiler_flags -floop-nest-optimize"
    else
        # Clang optimizations
        local compiler_flags="-finline-functions -fstrict-aliasing"
        compiler_flags="$compiler_flags -fslp-vectorize -fvectorize"
    fi
    
    # System flags
    local system_flags="-pthread -DHAS_LINUX_EPOLL -DBOOST_FIBER_NO_EXCEPTIONS"
    
    # Warning flags
    local warning_flags="-Wall -Wextra -Wno-unused-parameter -Wno-unused-variable"
    
    echo "$base_flags $ubuntu24_flags $arch_flags $compiler_flags $system_flags $warning_flags"
}

# Find source file to compile
find_source_file() {
    for source in "${SOURCE_FILES[@]}"; do
        if [ -f "$source" ]; then
            echo "$source"
            return 0
        fi
    done
    return 1
}

# Build with different compiler configurations
build_optimized() {
    highlight "🔧 BUILDING OPTIMIZED BINARY FOR UBUNTU 24"
    
    # Find source file
    SOURCE_FILE=$(find_source_file) || {
        error "No source file found. Available files should be one of: ${SOURCE_FILES[*]}"
        exit 1
    }
    
    log "Using source file: $SOURCE_FILE"
    
    # Test with both GCC and Clang
    local compilers=("g++-13" "clang++-18")
    local best_binary=""
    local best_compiler=""
    
    for compiler in "${compilers[@]}"; do
        if command -v "$compiler" > /dev/null; then
            log "Building with $compiler..."
            
            local flags=$(get_compiler_flags "$compiler")
            local output="${OUTPUT_BINARY}_${compiler//+*/}"
            local libs="-luring -lnuma -ljemalloc -pthread"
            
            info "Compiler flags: $flags"
            info "Libraries: $libs"
            
            # Compile with extensive logging
            if timeout 300 $compiler $flags -o "$output" "$SOURCE_FILE" $libs 2>&1 | tee -a "$BUILD_LOG"; then
                log "✅ Build successful with $compiler: $output"
                
                # Basic validation
                if [ -f "$output" ] && [ -x "$output" ]; then
                    log "Binary validation passed: $(file "$output")"
                    best_binary="$output"
                    best_compiler="$compiler"
                else
                    warn "Binary validation failed for $output"
                fi
            else
                warn "Build failed with $compiler"
            fi
        else
            warn "$compiler not available"
        fi
    done
    
    if [ -n "$best_binary" ]; then
        # Create optimized version with jemalloc
        log "Creating final optimized version..."
        cp "$best_binary" "$OUTPUT_BINARY"
        
        # Create launcher script with optimal runtime settings
        create_launcher_script
        
        log "✅ Build complete: $OUTPUT_BINARY (compiled with $best_compiler)"
        return 0
    else
        error "All builds failed"
        return 1
    fi
}

# Create optimized launcher script
create_launcher_script() {
    local launcher="${OUTPUT_BINARY}-launcher"
    
    cat > "$launcher" << 'LAUNCHER'
#!/bin/bash
# Meteor Ubuntu 24 Optimized Launcher

# Set CPU affinity and NUMA binding
export OMP_NUM_THREADS=$(($(nproc) / 2))
export MALLOC_ARENA_MAX=4

# Use jemalloc for better memory performance
export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD"

# Boost fiber optimizations
export BOOST_FIBER_STACK_SIZE=65536

# CPU frequency and scaling
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1 || true

# Get the directory of this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Launch with optimal settings
exec numactl --cpunodebind=0 --membind=0 "$DIR/meteor-server-ubuntu24-optimized" "$@"
LAUNCHER

    chmod +x "$launcher"
    log "Created optimized launcher: $launcher"
}

# Performance validation
validate_performance() {
    highlight "🧪 PERFORMANCE VALIDATION"
    
    if [ ! -f "$OUTPUT_BINARY" ]; then
        error "Binary not found: $OUTPUT_BINARY"
        return 1
    fi
    
    log "Starting performance validation..."
    
    # Basic functionality test
    timeout 30 ./"$OUTPUT_BINARY" --help > /dev/null 2>&1 || {
        warn "Binary help test failed"
        return 1
    }
    
    # Library dependency check
    log "Checking library dependencies..."
    ldd "$OUTPUT_BINARY" | grep -E "(not found|liburing|libboost|libjemalloc)" || true
    
    # Binary analysis
    log "Binary analysis:"
    file "$OUTPUT_BINARY"
    ls -lah "$OUTPUT_BINARY"
    
    # Performance hints
    info "Performance testing recommendations:"
    echo "  1. Test with different core counts: -c 4, -c 8, -c 16"
    echo "  2. Compare with Ubuntu 22 build using same memtier_benchmark parameters"
    echo "  3. Monitor CPU utilization and memory usage"
    echo "  4. Use: memtier_benchmark --server=127.0.0.1 --port=6379 --clients=50 --threads=8 --pipeline=20"
    
    log "Validation complete"
}

# Main workflow
main() {
    print_banner
    echo ""
    
    detect_system
    echo ""
    
    if [ "${1:-}" == "--install-deps" ]; then
        install_dependencies
        configure_system
        echo ""
    fi
    
    build_optimized
    echo ""
    
    validate_performance
    echo ""
    
    highlight "🎯 UBUNTU 24 REBUILD COMPLETE"
    echo "=============================="
    echo "✅ Optimized binary: $OUTPUT_BINARY"
    echo "✅ Launcher script: ${OUTPUT_BINARY}-launcher"
    echo "✅ Build log: $BUILD_LOG"
    echo ""
    echo "Next steps:"
    echo "1. Test performance with: ./${OUTPUT_BINARY}-launcher -c 4 -p 6379"
    echo "2. Compare QPS with Ubuntu 22 build"
    echo "3. Run comprehensive benchmarks"
    echo ""
}

# Handle arguments
if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
    echo "Usage: $0 [--install-deps|--help]"
    echo "  --install-deps  Install system dependencies and configure system"
    echo "  --help         Show this help message"
    exit 0
fi

main "$@"










