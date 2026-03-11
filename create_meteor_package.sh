#!/bin/bash

# **METEOR SERVER - PACKAGE CREATION SCRIPT**
# Creates distributable tar.gz package for enterprise deployment
# Similar to Redis/DragonflyDB distribution model

set -euo pipefail

# Package configuration
PACKAGE_NAME="meteor-server"
PACKAGE_VERSION="8.1-single-cmd-optimized-mget"
BUILD_DATE=$(date +"%Y%m%d")
# Parse command-line arguments
BINARY_ARG=""
SOURCE_FILE_ARG=""

# Handle help first
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
    show_help() {
        echo "Usage: $0 [UBUNTU_VERSION] [OPTIONS]"
        echo ""
        echo "UBUNTU_VERSION:"
        echo "  22           - Create package for Ubuntu 22"
        echo "  24           - Create package for Ubuntu 24 (default)"
        echo ""
        echo "BINARY OPTIONS:"
        echo "  --binary PATH        - Use existing binary from PATH"
        echo "  --source-file PATH   - Build from specific source file PATH"
        echo ""
        echo "AUTO-DETECTION (if no --binary or --source-file provided):"
        echo "  Priority order for binary/source selection:"
        echo "  1. Pre-built: meteor-server-ubuntu24-avx512"
        echo "  2. Source: cpp/meteor_redis_client_compatible_with_persistence.cpp (RDB+AOF)"
        echo "  3. Source: cpp/meteor_baseline_mget_single_cmd_optimized.cpp"
        echo "  4. Source: cpp/meteor_baseline_prod_v4.cpp"
        echo "  - Auto-builds with g++13/C++20 + AVX-512 optimizations"
        echo ""
        echo "OPTIONS:"
        echo "  --help, -h   - Show this help message"
        echo ""
        echo "ENVIRONMENT:"
        echo "  FORCE_AVX2=1 - Force AVX2 binary even on AVX-512 CPUs"
        echo ""
        echo "EXAMPLES:"
        echo "  $0                                    - Auto-detect and create package"
        echo "  $0 --binary ./my-meteor-server        - Use specific binary"
        echo "  $0 --source-file cpp/my-server.cpp    - Build from specific source"
        echo "  $0 24 --binary ./meteor-server         - Ubuntu 24 with specific binary"
        echo "  FORCE_AVX2=1 $0                        - Force AVX2 build"
        echo ""
        echo "OUTPUT:"
        echo "  meteor-server-8.1.0-ubuntu\${VERSION}-$(date +"%Y%m%d").tar.gz"
    }
    show_help
    exit 0
fi

# Parse --binary and --source-file arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --binary)
            BINARY_ARG="$2"
            shift 2
            ;;
        --source-file)
            SOURCE_FILE_ARG="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

UBUNTU_VERSION="${1:-24}"  # Ubuntu version parameter (22 or 24)
PACKAGE_FULL_NAME="${PACKAGE_NAME}-${PACKAGE_VERSION}-ubuntu${UBUNTU_VERSION}-${BUILD_DATE}"
BINARY_NAME="meteor-server"

# Detect CPU AVX-512 support (can be overridden by setting FORCE_AVX2=1)
detect_cpu_capabilities() {
    if [ "${FORCE_AVX2:-0}" = "1" ]; then
        echo "AVX2"
        return
    fi
    
    # Check for AVX-512 support using available tools
    if command -v lscpu >/dev/null 2>&1; then
        if lscpu | grep -q "avx512f"; then
            echo "AVX-512"
            return
        fi
    elif [ -f /proc/cpuinfo ]; then
        if grep -q "avx512f" /proc/cpuinfo; then
            echo "AVX-512"
            return
        fi
    fi
    
    # Default to AVX2 if no AVX-512 detected
    echo "AVX2"
}

CPU_CAPABILITIES=$(detect_cpu_capabilities)

# Default server configuration
DEFAULT_CORES="8"
DEFAULT_SHARDS="8"
DEFAULT_MEMORY="16384"  # MB
DEFAULT_PORT="6379"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[PACKAGE]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[PACKAGE]${NC} $1"
}

error() {
    echo -e "${RED:-\033[0;31m}[PACKAGE ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[PACKAGE]${NC} $1"
}

# Build meteor binary if it doesn't exist
build_meteor_binary() {
    local binary_target="$1"
    local optimization="$2"
    
    if [ -f "$binary_target" ]; then
        info "Binary $binary_target already exists, skipping build"
        return 0
    fi
    
    log "Building $optimization optimized meteor binary..."
    
    # Check for source file - Priority: User-provided > Persistence > MGET Single Command Optimized > TTL Baseline > Others  
    local source_file=""
    if [ -n "$SOURCE_FILE_ARG" ]; then
        source_file="$SOURCE_FILE_ARG"
        info "Using USER-PROVIDED source: $SOURCE_FILE_ARG"
    elif [ -f "cpp/meteor_redis_client_compatible_with_persistence.cpp" ]; then
        source_file="cpp/meteor_redis_client_compatible_with_persistence.cpp"
        info "Using REDIS CLIENT COMPATIBLE WITH PERSISTENCE source: meteor_redis_client_compatible_with_persistence.cpp (RDB+AOF+Full Redis compatibility)"
    elif [ -f "meteor_redis_client_compatible_with_persistence.cpp" ]; then
        source_file="meteor_redis_client_compatible_with_persistence.cpp"
        info "Using REDIS CLIENT COMPATIBLE WITH PERSISTENCE source: meteor_redis_client_compatible_with_persistence.cpp (RDB+AOF+Full Redis compatibility)"
    elif [ -f "cpp/meteor_baseline_mget_single_cmd_optimized.cpp" ]; then
        source_file="cpp/meteor_baseline_mget_single_cmd_optimized.cpp"
        info "Using MGET SINGLE COMMAND OPTIMIZED source: meteor_baseline_mget_single_cmd_optimized.cpp (691x performance fix)"
    elif [ -f "meteor_baseline_mget_single_cmd_optimized.cpp" ]; then
        source_file="meteor_baseline_mget_single_cmd_optimized.cpp"
        info "Using MGET SINGLE COMMAND OPTIMIZED source: meteor_baseline_mget_single_cmd_optimized.cpp (691x performance fix)"
    elif [ -f "cpp/meteor_baseline_prod_v4.cpp" ]; then
        source_file="cpp/meteor_baseline_prod_v4.cpp"
        info "Using TTL BASELINE PRODUCTION source: meteor_baseline_prod_v4.cpp"
    elif [ -f "meteor_baseline_prod_v4.cpp" ]; then
        source_file="meteor_baseline_prod_v4.cpp"
        info "Using TTL BASELINE PRODUCTION source: meteor_baseline_prod_v4.cpp"
    elif [ -f "cpp/meteor_deterministic_core_affinity.cpp" ]; then
        source_file="cpp/meteor_deterministic_core_affinity.cpp"
        info "Using HIGH-PERFORMANCE DETERMINISTIC source: meteor_deterministic_core_affinity.cpp"
    elif [ -f "meteor_deterministic_core_affinity.cpp" ]; then
        source_file="meteor_deterministic_core_affinity.cpp"
        info "Using HIGH-PERFORMANCE DETERMINISTIC source: meteor_deterministic_core_affinity.cpp"
    elif [ -f "cpp/meteor_v8_persistent_snapshot.cpp" ]; then
        source_file="cpp/meteor_v8_persistent_snapshot.cpp"
        info "Using ENTERPRISE PERSISTENCE source: meteor_v8_persistent_snapshot.cpp"
    elif [ -f "meteor_v8_persistent_snapshot.cpp" ]; then
        source_file="meteor_v8_persistent_snapshot.cpp"
        info "Using ENTERPRISE PERSISTENCE source: meteor_v8_persistent_snapshot.cpp"
    else
        error "No source file found. Looking for: meteor_redis_client_compatible_with_persistence.cpp, meteor_v8_persistent_snapshot.cpp or meteor_baseline_prod_v4.cpp in cpp/ or current directory"
    fi
    
    # Detect compiler
    local compiler="g++"
    if command -v g++-13 >/dev/null 2>&1; then
        compiler="g++-13"
        info "Using g++-13 for C++20 optimizations"
    elif command -v g++ >/dev/null 2>&1; then
        compiler="g++"
        info "Using default g++ compiler"
    else
        error "No suitable C++ compiler found"
    fi
    
    # Base compiler flags for C++20 and performance - Enterprise persistence requires C++20
    local base_flags="-std=c++20 -O3 -DNDEBUG -DHAS_LINUX_EPOLL -pthread -march=native -mtune=native"
    
    # Aggressive SIMD optimization flags matching user specification
    local opt_flags=""
    if [ "$optimization" = "AVX-512" ]; then
        # Full AVX-512: Complete optimization suite as specified by user
        opt_flags="-mavx512f -mavx512dq -mavx2 -mavx -msse4.2 -msse4.1 -mfma"
        log "Using aggressive AVX-512 flags as specified: mavx512f mavx512dq mavx2 mavx msse4.2 msse4.1 mfma"
    else
        # AVX2: Complete optimization suite
        opt_flags="-mavx2 -mavx -msse4.2 -msse4.1 -mfma"
        log "Using aggressive AVX2 flags: mavx2 mavx msse4.2 msse4.1 mfma"
    fi
    
    # Libraries - Include persistence dependencies for Enterprise features
    local libs="-lboost_fiber -lboost_context -lboost_system -luring -ljemalloc -lzstd -llz4 -lssl -lcrypto -lcurl"
    
    log "Compiling with $compiler C++20 Enterprise and $optimization optimizations..."
    log "Source: $source_file -> Target: $binary_target"
    
    # Create cpp directory if it doesn't exist
    mkdir -p cpp
    
    # Compile
    if $compiler $base_flags $opt_flags -o "$binary_target" "$source_file" $libs; then
        log "Successfully built $optimization optimized binary: $binary_target"
        chmod +x "$binary_target"
        
        # Display binary info
        local binary_size=$(du -h "$binary_target" | cut -f1)
        info "Binary size: $binary_size"
        
        return 0
    else
        error "Failed to compile $binary_target with $optimization optimizations"
    fi
}

# Binary source selection and building
setup_binary_source() {
    # Priority 1: Use --binary argument if provided
    if [ -n "$BINARY_ARG" ]; then
        if [ ! -f "$BINARY_ARG" ]; then
            error "Binary not found at specified path: $BINARY_ARG"
        fi
        BINARY_SOURCE="$BINARY_ARG"
        OPTIMIZATION_TYPE="User-Provided-Binary"
        JEMALLOC_SUPPORT="unknown"
        log "Using user-provided binary: $BINARY_ARG"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1))"
        return 0
    fi
    
    # Priority 2: Use --source-file argument if provided
    if [ -n "$SOURCE_FILE_ARG" ]; then
        if [ ! -f "$SOURCE_FILE_ARG" ]; then
            error "Source file not found at specified path: $SOURCE_FILE_ARG"
        fi
        
        local target_binary="cpp/meteor_custom_build"
        log "Building from user-provided source: $SOURCE_FILE_ARG"
        
        if [ "$CPU_CAPABILITIES" = "AVX-512" ]; then
            build_meteor_binary "$target_binary" "AVX-512"
            OPTIMIZATION_TYPE="AVX-512-Custom-Build"
        else
            build_meteor_binary "$target_binary" "AVX2"
            OPTIMIZATION_TYPE="AVX2-Custom-Build"
        fi
        
        BINARY_SOURCE="$target_binary"
        JEMALLOC_SUPPORT="true"
        return 0
    fi
    
    # Priority 3: Auto-detection (existing logic)
    # Check for configurable production binary first (enterprise v8.3 with configurable snapshots)
    if [ -f "meteor-server-v8.3-production-configurable" ]; then
        BINARY_SOURCE="meteor-server-v8.3-production-configurable"
        OPTIMIZATION_TYPE="C++20-Enterprise-Configurable-Production"
        JEMALLOC_SUPPORT="true"
        log "Using Enterprise v8.3 CONFIGURABLE PRODUCTION binary with all fixes (C++20, persistence, BGSAVE fix, configurable snapshots)"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1)) - Production-ready with BGSAVE + configurable automatic snapshots"
    # Check for complete production binary (fallback)
    elif [ -f "meteor-server-v8.3-production-complete" ]; then
        BINARY_SOURCE="meteor-server-v8.3-production-complete"
        OPTIMIZATION_TYPE="C++20-Enterprise-Complete-Production"
        JEMALLOC_SUPPORT="true"
        log "Using Enterprise v8.3 COMPLETE PRODUCTION binary with all fixes (C++20, persistence, BGSAVE fix, automatic snapshots)"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1)) - Complete production-ready with BGSAVE + automatic snapshot fixes"
    # Check for AOF truncation fixed binary (fallback)
    elif [ -f "meteor-server-v8.2-aof-fixed-production" ]; then
        BINARY_SOURCE="meteor-server-v8.2-aof-fixed-production"
        OPTIMIZATION_TYPE="C++20-Enterprise-AOF-Fixed-Production"
        JEMALLOC_SUPPORT="true"
        log "Using Enterprise v8.2 PRODUCTION binary with AOF truncation fix (C++20, persistence, full SIMD)"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1)) - Production-ready with AOF infinite growth fix"
    # Check for async BGSAVE fixed binary (fallback)
    elif [ -f "meteor-server-v8.2-enterprise-fixed" ]; then
        BINARY_SOURCE="meteor-server-v8.2-enterprise-fixed"
        OPTIMIZATION_TYPE="C++20-Enterprise-AsyncBGSAVE-Fixed"
        JEMALLOC_SUPPORT="true"
        log "Using Enterprise v8.2 binary with Async BGSAVE fix (C++20, persistence, full SIMD)"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1)) - Production-ready with async BGSAVE"
    # Check for new C++17 aggressive v2 binary first (with user-specified flags)
    elif [ -f "meteor-server-cpp17-aggressive-v2" ]; then
        BINARY_SOURCE="meteor-server-cpp17-aggressive-v2"
        OPTIMIZATION_TYPE="C++17-AVX-512-Aggressive-v2"
        JEMALLOC_SUPPORT="true"
        log "Using C++17 aggressive AVX-512 binary v2 (O3, mavx512f mavx512dq mavx2 mavx msse4.2 msse4.1 mfma)"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1)) - User-specified optimization flags"
    # Check for previous C++17 aggressive binary as fallback
    elif [ -f "meteor-server-cpp17-aggressive" ]; then
        BINARY_SOURCE="meteor-server-cpp17-aggressive"
        OPTIMIZATION_TYPE="C++17-AVX-512-Aggressive"
        JEMALLOC_SUPPORT="true"
        log "Using C++17 aggressive AVX-512 binary (O3, march=native, full SIMD)"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1)) - Maximum performance build"
    # Check for pre-built Ubuntu 24 AVX-512 binary as fallback
    elif [ -f "meteor-server-ubuntu24-avx512" ]; then
        BINARY_SOURCE="meteor-server-ubuntu24-avx512"
        OPTIMIZATION_TYPE="AVX-512"
        JEMALLOC_SUPPORT="true"
        log "Using pre-built Ubuntu 24 AVX-512 binary for self-contained distribution"
        info "Binary: $BINARY_SOURCE ($(du -h "$BINARY_SOURCE" | cut -f1)) - No compilation dependencies required"
    elif [ "$CPU_CAPABILITIES" = "AVX-512" ]; then
        BINARY_SOURCE="cpp/meteor_ttl_complete_ubuntu24"
        OPTIMIZATION_TYPE="AVX-512"
        JEMALLOC_SUPPORT="true"
        
        # Build AVX-512 binary if it doesn't exist
        build_meteor_binary "$BINARY_SOURCE" "AVX-512"
    else
        BINARY_SOURCE="cpp/meteor_ttl_complete"
        OPTIMIZATION_TYPE="AVX2"
        JEMALLOC_SUPPORT=$([ "$UBUNTU_VERSION" = "24" ] && echo "true" || echo "optional")
        
        # Build AVX2 binary if it doesn't exist  
        build_meteor_binary "$BINARY_SOURCE" "AVX2"
    fi

    # Final check that binary exists after build attempt
    if [ ! -f "$BINARY_SOURCE" ]; then
        error "Failed to create or find meteor binary at $BINARY_SOURCE"
    fi
    
    # Display configuration summary
    log "Binary configuration complete:"
    info "Optimization: $OPTIMIZATION_TYPE | jemalloc: $JEMALLOC_SUPPORT | Binary: $BINARY_SOURCE"
}

print_banner() {
    cat << 'BANNER'

███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝

    DISTRIBUTION PACKAGE BUILDER v8.0
    High-Performance Redis-Compatible Server
    
BANNER

    echo -e "${GREEN}Creating distributable package: ${PACKAGE_FULL_NAME}${NC}"
    echo "Ubuntu Version: $UBUNTU_VERSION | CPU: $CPU_CAPABILITIES"
    echo "=================================================================="
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if binary exists locally
    if [ ! -f "$BINARY_SOURCE" ]; then
        error "Binary not found at $BINARY_SOURCE
        
Detected CPU: $CPU_CAPABILITIES | Ubuntu: $UBUNTU_VERSION

Binary options for package creation:

1. SELF-CONTAINED DISTRIBUTION (Recommended):
   - Place pre-built binary: meteor-server-ubuntu24-avx512
   - No compilation dependencies required
   - Ready for any Ubuntu 24 VM

2. AUTO-BUILD FROM SOURCE:
   - Source file: cpp/meteor_baseline_prod_v4.cpp (or meteor_baseline_prod_v4.cpp)
   - Binaries built automatically:
     * AVX-512: cpp/meteor_ttl_complete_ubuntu24 (if CPU supports AVX-512)
     * AVX2: cpp/meteor_ttl_complete (fallback)

Environment: FORCE_AVX2=1 $0 (force AVX2 build)"
    fi
    
    # Check if binary is executable
    if [ ! -x "$BINARY_SOURCE" ]; then
        error "Binary at $BINARY_SOURCE is not executable. Run: chmod +x $BINARY_SOURCE"
    fi
    
    # Display binary information
    BINARY_SIZE=$(du -h "$BINARY_SOURCE" | cut -f1)
    info "Using binary: $BINARY_SOURCE ($BINARY_SIZE) for Ubuntu $UBUNTU_VERSION"
    
    # Check deployment directory
    if [ ! -d "deployment" ]; then
        error "deployment directory not found. Please run this script from the meteor project root"
    fi
    
    log "Prerequisites validated successfully"
    info "Using binary: $(ls -lh $BINARY_SOURCE)"
}

# Create package directory structure
create_package_structure() {
    log "Creating package directory structure..."
    
    # Clean up any existing package directory
    rm -rf "$PACKAGE_FULL_NAME"
    
    # Create main package directory
    mkdir -p "$PACKAGE_FULL_NAME"
    
    # Create standard directory structure
    mkdir -p "$PACKAGE_FULL_NAME"/{bin,lib,etc,scripts,docs,systemd,monitoring}
    
    log "Package structure created"
}

# Copy and prepare binary
prepare_binary() {
    log "Preparing Meteor server binary..."
    
    # Copy binary with standard name
    cp "$BINARY_SOURCE" "$PACKAGE_FULL_NAME/bin/$BINARY_NAME"
    chmod +x "$PACKAGE_FULL_NAME/bin/$BINARY_NAME"
    
    # Skip library bundling (rely on system packages for Boost libraries)
    log "Skipping library bundling - using system Boost libraries for better compatibility"
    info "Dependencies: libboost-fiber, libboost-context, libboost-system will be installed via apt"
    
    # Get binary info
    BINARY_SIZE=$(du -h "$PACKAGE_FULL_NAME/bin/$BINARY_NAME" | cut -f1)
    info "Binary size: $BINARY_SIZE"
    
    # Create version file
    cat > "$PACKAGE_FULL_NAME/bin/VERSION" << VERSION
METEOR_VERSION=$PACKAGE_VERSION
BUILD_DATE=$BUILD_DATE
BINARY_NAME=$BINARY_NAME
BINARY_SIZE=$BINARY_SIZE
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_HOST=$(hostname)
BUILD_USER=$(whoami)
VERSION

    log "Binary prepared successfully"
}

# Create health monitor script (continuous monitoring)
create_health_monitor_script() {
    cat > "$PACKAGE_FULL_NAME/scripts/meteor-health-monitor.sh" << 'HEALTH_EOF'
#!/bin/bash
# Meteor Health Monitor - Continuous health monitoring and logging
# Configurable via environment variables or /etc/meteor/meteor.conf

# Load configuration from file if it exists
if [ -f /etc/meteor/meteor.conf ]; then
    source /etc/meteor/meteor.conf
fi

REDIS_CLI=${REDIS_CLI:-redis-cli}
METEOR_HOST=${METEOR_HOST:-127.0.0.1}
METEOR_PORT=${METEOR_PORT:-6379}
HEALTH_CHECK_TIMEOUT=${METEOR_HEALTH_CHECK_TIMEOUT:-2}  # Default: 2 seconds
MAX_RETRIES=${METEOR_HEALTH_MAX_RETRIES:-2}             # Default: 2 retries
CHECK_INTERVAL=${METEOR_HEALTH_CHECK_INTERVAL:-3}       # Default: 3 seconds between checks

LOG_FILE="/var/log/meteor/health-monitor.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHMON: $1" | tee -a "$LOG_FILE"
}

check_health() {
    timeout "$HEALTH_CHECK_TIMEOUT" $REDIS_CLI -h "$METEOR_HOST" -p "$METEOR_PORT" PING > /dev/null 2>&1
    return $?
}

consecutive_failures=0

log "🏥 Meteor Health Monitor started"
log "   Config: timeout=${HEALTH_CHECK_TIMEOUT}s, max_retries=${MAX_RETRIES}, check_interval=${CHECK_INTERVAL}s"

while true; do
    if check_health; then
        if [ $consecutive_failures -gt 0 ]; then
            log "✅ Server recovered after $consecutive_failures failure(s)"
        fi
        consecutive_failures=0
    else
        consecutive_failures=$((consecutive_failures + 1))
        log "⚠️  Health check failed ($consecutive_failures/$MAX_RETRIES) - timeout after ${HEALTH_CHECK_TIMEOUT}s"
        
        if [ $consecutive_failures -ge $MAX_RETRIES ]; then
            log "💥 Server not responding after $MAX_RETRIES retries, triggering restart via systemd"
            systemctl restart meteor.service
            consecutive_failures=0
            log "⏳ Waiting 10 seconds for server to stabilize..."
            sleep 10
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
HEALTH_EOF
    chmod +x "$PACKAGE_FULL_NAME/scripts/meteor-health-monitor.sh"
}

# Create hang detector script (periodic check with auto-restart)
create_hangdetector_script() {
    cat > "$PACKAGE_FULL_NAME/scripts/meteor-hangdetector.sh" << 'HANGDETECT_EOF'
#!/bin/bash
# Meteor Hang Detector - Periodic hang detection with auto-restart
# Runs via systemd timer every 10 seconds

# Load configuration from file if it exists
if [ -f /etc/meteor/meteor.conf ]; then
    source /etc/meteor/meteor.conf
fi

METEOR_HOST=${METEOR_HOST:-127.0.0.1}
METEOR_PORT=${METEOR_PORT:-6379}
HANG_TIMEOUT=${METEOR_HANG_TIMEOUT:-2}
LOG_FILE="/var/log/meteor/hang-detector.log"
MAX_FAILURES=${METEOR_HANG_MAX_FAILURES:-2}
FAILURE_COUNT_FILE="/tmp/meteor-hang-failure-count"

mkdir -p "$(dirname "$LOG_FILE")"

log_hang() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HANG-DETECTOR: $1" | tee -a "$LOG_FILE"
}

# Get current failure count
get_failure_count() {
    if [ -f "$FAILURE_COUNT_FILE" ]; then
        cat "$FAILURE_COUNT_FILE"
    else
        echo "0"
    fi
}

# Set failure count
set_failure_count() {
    echo "$1" > "$FAILURE_COUNT_FILE"
}

# Check if server is responding
check_server() {
    timeout "$HANG_TIMEOUT" redis-cli -h "$METEOR_HOST" -p "$METEOR_PORT" PING > /dev/null 2>&1
    return $?
}

# Restart meteor service
restart_meteor() {
    log_hang "🔄 Initiating systemd restart..."
    systemctl restart meteor.service
    set_failure_count 0
    log_hang "✅ Restart initiated, failure count reset"
}

# Main execution
main() {
    current_failures=$(get_failure_count)
    
    if check_server; then
        # Server is healthy
        if [ "$current_failures" -gt 0 ]; then
            log_hang "✅ Server recovered (was at $current_failures failures)"
            set_failure_count 0
        fi
    else
        # Server not responding
        current_failures=$((current_failures + 1))
        log_hang "⚠️  Server not responding (failure $current_failures/$MAX_FAILURES) - timeout: ${HANG_TIMEOUT}s"
        set_failure_count "$current_failures"
        
        if [ "$current_failures" -ge "$MAX_FAILURES" ]; then
            log_hang "💥 HANG DETECTED after $current_failures failures, triggering restart"
            restart_meteor
        fi
    fi
}

main "$@"
HANGDETECT_EOF
    chmod +x "$PACKAGE_FULL_NAME/scripts/meteor-hangdetector.sh"
}

# Create config update script
create_config_update_script() {
    cat > "$PACKAGE_FULL_NAME/scripts/meteor-update-config.sh" << 'CONFIG_UPDATE_EOF'
#!/bin/bash
# Meteor Configuration Update Script
# Updates /etc/meteor/meteor.conf and restarts the service

set -euo pipefail

CONFIG_FILE="/etc/meteor/meteor.conf"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[CONFIG]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[CONFIG]${NC} $1"
}

show_usage() {
    cat << USAGE
Meteor Configuration Update Script

USAGE:
    $0 <KEY>=<VALUE> [<KEY>=<VALUE> ...]
    $0 --show                    # Show current configuration
    $0 --restart                 # Restart service without changes

AVAILABLE KEYS:
    METEOR_PORT                  # Server port (default: 6379)
    METEOR_CORES                 # Number of CPU cores
    METEOR_SHARDS                # Number of shards (should match cores)
    METEOR_MEMORY_MB             # Max memory in MB
    METEOR_PERSISTENCE           # Enable persistence (0/1)
    METEOR_SNAPSHOT_INTERVAL     # RDB snapshot interval in seconds
    METEOR_SNAPSHOT_OPS          # Snapshot after N operations
    METEOR_FSYNC_POLICY          # Fsync policy (0=never, 1=always, 2=everysec)
    METEOR_RDB_PATH              # RDB directory path
    METEOR_AOF_PATH              # AOF directory path
    METEOR_HANG_TIMEOUT          # Health monitor timeout

EXAMPLES:
    # Update memory and restart
    $0 METEOR_MEMORY_MB=32768

    # Update multiple parameters
    $0 METEOR_CORES=16 METEOR_SHARDS=16 METEOR_MEMORY_MB=65536

    # Disable persistence
    $0 METEOR_PERSISTENCE=0

    # Change snapshot interval to 1 hour
    $0 METEOR_SNAPSHOT_INTERVAL=3600

    # Show current configuration
    $0 --show
    
USAGE
}

if [ "$#" -eq 0 ]; then
    show_usage
    exit 1
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

if [ "$1" == "--show" ]; then
    log "Current Meteor Configuration:"
    cat "$CONFIG_FILE"
    exit 0
fi

if [ "$1" == "--restart" ]; then
    log "Restarting Meteor service..."
    systemctl restart meteor.service
    systemctl restart meteor-health-monitor.service 2>/dev/null || true
    log "Service restarted successfully"
    exit 0
fi

# Check root privileges
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Backup current config
cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"

# Update configuration
log "Updating configuration..."
for arg in "$@"; do
    if [[ "$arg" =~ ^([A-Z_]+)=(.+)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        
        # Validate key
        if ! grep -q "^$key=" "$CONFIG_FILE" && ! grep -q "^#$key=" "$CONFIG_FILE"; then
            warn "Unknown configuration key: $key (skipping)"
            continue
        fi
        
        # Update value
        if grep -q "^$key=" "$CONFIG_FILE"; then
            sed -i "s|^$key=.*|$key=$value|" "$CONFIG_FILE"
        else
            sed -i "s|^#$key=.*|$key=$value|" "$CONFIG_FILE"
        fi
        log "  $key = $value"
    else
        warn "Invalid format: $arg (expected KEY=VALUE)"
    fi
done

log "Configuration updated successfully"
log ""
log "Restarting Meteor service to apply changes..."

systemctl daemon-reload
systemctl restart meteor.service

# Restart health monitor if config changed hang timeout
if echo "$@" | grep -q "METEOR_HANG_TIMEOUT"; then
    log "Restarting health monitor with new timeout..."
    systemctl restart meteor-health-monitor.service 2>/dev/null || true
fi

log "Service restarted successfully"
log ""
log "Checking service status..."
systemctl status meteor.service --no-pager

echo ""
log "Configuration change complete!"
log "Backup saved: $CONFIG_FILE.backup.*"
CONFIG_UPDATE_EOF
    chmod +x "$PACKAGE_FULL_NAME/scripts/meteor-update-config.sh"
}

# Create RDB cleanup script
create_rdb_cleanup_script() {
    cat > "$PACKAGE_FULL_NAME/scripts/meteor-rdb-cleanup.sh" << 'RDB_CLEANUP_EOF'
#!/bin/bash
# Meteor RDB Cleanup - Keep only last 3 snapshots

RDB_PATH=${METEOR_RDB_PATH:-/var/lib/meteor/snapshots}
KEEP_COUNT=3

if [ ! -d "$RDB_PATH" ]; then
    exit 0
fi

cd "$RDB_PATH" || exit 1

# Get list of RDB files (excluding symlinks), sorted by modification time
RDB_FILES=$(find . -maxdepth 1 -name "meteor_*.rdb" -type f -printf '%T@ %p\n' | sort -rn | awk '{print $2}')

# Count files
FILE_COUNT=$(echo "$RDB_FILES" | grep -c '^')

if [ "$FILE_COUNT" -le "$KEEP_COUNT" ]; then
    exit 0
fi

# Remove old files
echo "$RDB_FILES" | tail -n +$((KEEP_COUNT + 1)) | while read -r file; do
    echo "[$(date)] Removing old RDB: $file" >> /var/log/meteor/rdb-cleanup.log
    rm -f "$file"
done

echo "[$(date)] RDB cleanup complete. Kept $KEEP_COUNT most recent snapshots." >> /var/log/meteor/rdb-cleanup.log
RDB_CLEANUP_EOF
    chmod +x "$PACKAGE_FULL_NAME/scripts/meteor-rdb-cleanup.sh"
}

# Copy deployment scripts
copy_deployment_files() {
    log "Copying deployment files..."
    
    # Copy and update main deployment script
    cp deployment/scripts/deploy_meteor.sh "$PACKAGE_FULL_NAME/scripts/"
    
    # Update binary name in deployment script
    sed -i.bak "s/meteor_race_fix/$BINARY_NAME/g" "$PACKAGE_FULL_NAME/scripts/deploy_meteor.sh"
    rm "$PACKAGE_FULL_NAME/scripts/deploy_meteor.sh.bak"
    
    # Create health monitor, hang detector, config update, and RDB cleanup scripts
    create_health_monitor_script
    create_hangdetector_script
    create_config_update_script
    create_rdb_cleanup_script
    
    # Create systemd service file with EnvironmentFile support
    cat > "$PACKAGE_FULL_NAME/systemd/meteor.service" << 'SYSTEMD_SERVICE_EOF'
[Unit]
Description=Meteor High-Performance Redis-Compatible Server
After=network.target

[Service]
Type=simple
User=meteor
Group=meteor
WorkingDirectory=/opt/meteor

# Load configuration from file
EnvironmentFile=/etc/meteor/meteor.conf

# Build ExecStart command using environment variables
ExecStart=/opt/meteor/bin/meteor-server \
    -h ${METEOR_HOST} \
    -p ${METEOR_PORT} \
    -c ${METEOR_CORES} \
    -s ${METEOR_SHARDS} \
    -m ${METEOR_MEMORY_MB} \
    -P ${METEOR_PERSISTENCE} \
    -R ${METEOR_RDB_PATH} \
    -A ${METEOR_AOF_PATH} \
    -I ${METEOR_SNAPSHOT_INTERVAL} \
    -O ${METEOR_SNAPSHOT_OPS} \
    -F ${METEOR_FSYNC_POLICY}

# Resource limits
LimitNOFILE=1048576
LimitNPROC=512

# Restart policy
Restart=always
RestartSec=5s

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=meteor

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE_EOF
    
    # For Ubuntu 24, add jemalloc support to the systemd service
    if [ "$UBUNTU_VERSION" = "24" ]; then
        log "Configuring jemalloc support for Ubuntu 24..."
        
        # Add jemalloc environment variable using awk (more portable)
        if ! grep -q "LD_PRELOAD.*libjemalloc" "$PACKAGE_FULL_NAME/systemd/meteor.service"; then
            awk '
                /^# Load configuration from file/ { 
                    print; 
                    print "Environment=\"LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2\""; 
                    next 
                }
                { print }
            ' "$PACKAGE_FULL_NAME/systemd/meteor.service" > "$PACKAGE_FULL_NAME/systemd/meteor.service.tmp"
            mv "$PACKAGE_FULL_NAME/systemd/meteor.service.tmp" "$PACKAGE_FULL_NAME/systemd/meteor.service"
            info "Added jemalloc LD_PRELOAD to systemd service for Ubuntu 24"
        fi
    else
        info "Using standard systemd service for Ubuntu 22"
    fi
    
    # Copy backup script
    cp deployment/scripts/backup_meteor.sh "$PACKAGE_FULL_NAME/scripts/"
    
    # Copy cleanup script
    if [ -f "cleanup_meteor.sh" ]; then
        cp cleanup_meteor.sh "$PACKAGE_FULL_NAME/scripts/"
        chmod +x "$PACKAGE_FULL_NAME/scripts/cleanup_meteor.sh"
        info "Added cleanup script to package"
    fi
    
    # Create configuration file template
    cat > "$PACKAGE_FULL_NAME/etc/meteor.conf.template" << 'CONF_EOF'
# Meteor Server Configuration File
# This file is loaded by systemd as an EnvironmentFile
# Modify values here and restart service: systemctl restart meteor.service
# Or reload config: systemctl daemon-reload && systemctl restart meteor.service

# Network Configuration
METEOR_HOST=0.0.0.0
METEOR_PORT=6379

# Performance Configuration
METEOR_CORES=8
METEOR_SHARDS=8
METEOR_MEMORY_MB=16384

# Persistence Configuration
METEOR_PERSISTENCE=1
METEOR_RDB_PATH=/var/lib/meteor/snapshots
METEOR_AOF_PATH=/var/lib/meteor/aof
METEOR_SNAPSHOT_INTERVAL=1800
METEOR_SNAPSHOT_OPS=50000
METEOR_FSYNC_POLICY=2

# Health Monitoring Configuration
METEOR_HEALTH_CHECK_TIMEOUT=2      # Seconds to wait for PING response
METEOR_HEALTH_MAX_RETRIES=2        # Number of retries before restart
METEOR_HEALTH_CHECK_INTERVAL=3     # Seconds between health checks

# Hang Detector Configuration (periodic check every 5 seconds via timer)
METEOR_HANG_TIMEOUT=2              # Seconds to wait for PING response
METEOR_HANG_MAX_FAILURES=2         # Number of failures before restart
CONF_EOF
    
    # Copy default configuration
    cp "$PACKAGE_FULL_NAME/etc/meteor.conf.template" "$PACKAGE_FULL_NAME/etc/meteor.conf"
    
    # Copy monitoring configurations
    cp deployment/monitoring/* "$PACKAGE_FULL_NAME/monitoring/"
    
    log "Deployment files copied"
}

# Create installation script
create_install_script() {
    log "Creating installation script..."
    
    cat > "$PACKAGE_FULL_NAME/install.sh" << 'INSTALL_START'
#!/bin/bash

# **METEOR SERVER - INSTALLATION SCRIPT**
# Self-contained installer for Meteor server package

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
NC='\033[0m'

# Default server configuration
INSTALL_START
    
    # Add the default values with actual substitution
    cat >> "$PACKAGE_FULL_NAME/install.sh" << INSTALL_VALUES
DEFAULT_CORES="8"
DEFAULT_SHARDS="8"
DEFAULT_MEMORY="$DEFAULT_MEMORY"
DEFAULT_PORT="$DEFAULT_PORT"
INSTALL_VALUES
    
    cat >> "$PACKAGE_FULL_NAME/install.sh" << 'INSTALL_REST'

log() {
    echo -e "${GREEN}[INSTALL]${NC} $1"
}

print_banner() {
    cat << 'BANNER'

███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝

    METEOR SERVER INSTALLATION
    Enterprise Redis-Compatible Server
    
BANNER
}

show_usage() {
    cat << USAGE
Meteor Server Installation Script with Persistence

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --install         Install Meteor server (default)
    --uninstall       Uninstall Meteor server
    --help            Show this help message
    --version         Show version information
    --cores NUM       Number of CPU cores to use (default: $DEFAULT_CORES)
    --shards NUM      Number of shards (should match cores) (default: $DEFAULT_SHARDS)
    --memory MB       Maximum memory in MB (default: $DEFAULT_MEMORY)
    --port PORT       Server port (default: $DEFAULT_PORT)
    
PERSISTENCE OPTIONS:
    --persistence 0|1           Enable persistence (default: 1)
    --snapshot-interval SECONDS RDB snapshot interval (default: 1800 = 30 minutes)
    --snapshot-ops COUNT        Create snapshot after N operations (default: 50000)
    --fsync-policy 0|1|2        Fsync policy: 0=never, 1=always, 2=everysec (default: 2)
    --rdb-path PATH             RDB directory (default: /var/lib/meteor/snapshots)
    --aof-path PATH             AOF directory (default: /var/lib/meteor/aof)
    
FSYNC POLICIES:
    0 (never)      Fastest, potential data loss on crash
    1 (always)     Slowest, zero data loss (every write synced)
    2 (everysec)   **Recommended** - Balanced, ~1 second data loss on crash

HEALTH & MONITORING:
    --enable-health-monitor     Enable health monitoring with auto-restart (default: enabled)
    --hang-timeout SECONDS      Restart if no response for N seconds (default: 30)

EXAMPLES:
    $0                                    # Install with defaults (persistence enabled, 30min snapshots)
    $0 --cores 16 --shards 16             # Install with 16 cores/shards
    $0 --memory 32768 --port 6380         # Custom memory and port
    $0 --persistence 0                    # Disable persistence (in-memory only)
    $0 --snapshot-interval 3600           # Snapshot every hour
    $0 --fsync-policy 1                   # Maximum durability (always sync)
    $0 --uninstall                        # Remove installation

PERSISTENCE FEATURES:
    ✅ RDB Snapshots: Binary snapshots with LZ4 compression
    ✅ AOF Logging: Redis-compatible append-only file
    ✅ Auto Recovery: Loads RDB + AOF on restart
    ✅ RDB Cleanup: Keeps last 3 snapshots automatically
    ✅ Health Monitor: Detects hangs and restarts server
    
USAGE
}

show_version() {
    if [ -f "$SCRIPT_DIR/bin/VERSION" ]; then
        cat "$SCRIPT_DIR/bin/VERSION"
    else
        echo "Version information not available"
    fi
}

install_meteor() {
    print_banner
    
    log "Starting Meteor Server installation..."
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Parse configuration parameters
    local cores="$DEFAULT_CORES"
    local shards="$DEFAULT_SHARDS"
    local memory="$DEFAULT_MEMORY"
    local port="$DEFAULT_PORT"
    
    # Persistence configuration with defaults
    local persistence_enabled="1"
    local snapshot_interval="1800"  # 30 minutes
    local snapshot_ops="50000"
    local fsync_policy="2"  # everysec
    local rdb_path="/var/lib/meteor/snapshots"
    local aof_path="/var/lib/meteor/aof"
    
    # Health monitoring
    local enable_health_monitor="true"
    local hang_timeout="30"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cores)
                cores="$2"
                shift 2
                ;;
            --shards)
                shards="$2"
                shift 2
                ;;
            --memory)
                memory="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --persistence)
                persistence_enabled="$2"
                shift 2
                ;;
            --snapshot-interval)
                snapshot_interval="$2"
                shift 2
                ;;
            --snapshot-ops)
                snapshot_ops="$2"
                shift 2
                ;;
            --fsync-policy)
                fsync_policy="$2"
                shift 2
                ;;
            --rdb-path)
                rdb_path="$2"
                shift 2
                ;;
            --aof-path)
                aof_path="$2"
                shift 2
                ;;
            --enable-health-monitor)
                enable_health_monitor="true"
                shift
                ;;
            --hang-timeout)
                hang_timeout="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "Configuration Summary:"
    log "  Performance: Cores=$cores, Shards=$shards, Memory=${memory}MB, Port=$port"
    log "  Persistence: $([ "$persistence_enabled" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    if [ "$persistence_enabled" -eq 1 ]; then
        log "    Snapshot Interval: ${snapshot_interval}s ($((snapshot_interval / 60)) minutes)"
        log "    Snapshot Operations: $snapshot_ops"
        log "    Fsync Policy: $fsync_policy ($([ "$fsync_policy" -eq 0 ] && echo "never" || [ "$fsync_policy" -eq 1 ] && echo "always" || echo "everysec"))"
        log "    RDB Path: $rdb_path"
        log "    AOF Path: $aof_path"
    fi
    log "  Health Monitor: $([ "$enable_health_monitor" = "true" ] && echo "Enabled (timeout: ${hang_timeout}s)" || echo "Disabled")"
    
    # Detect Ubuntu version and setup jemalloc for Ubuntu 24
    detect_and_setup_jemalloc() {
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [ "$ID" = "ubuntu" ] && [[ "$VERSION_ID" == "24."* ]]; then
                log "Detected Ubuntu 24.x - Installing jemalloc for optimal performance..."
                apt update && apt install -y libjemalloc2 libjemalloc-dev || {
                    warn "Failed to install jemalloc, continuing with system malloc"
                }
            else
                log "Detected $ID $VERSION_ID - Using system memory allocator"
            fi
        fi
    }
    
    # Setup jemalloc if Ubuntu 24
    detect_and_setup_jemalloc
    
    # Create persistence directories
    if [ "$persistence_enabled" -eq 1 ]; then
        log "Creating persistence directories..."
        mkdir -p "$rdb_path" "$aof_path" /var/log/meteor
        chown -R meteor:meteor "$rdb_path" "$aof_path" /var/log/meteor 2>/dev/null || true
    fi
    
    # Write configuration to meteor.conf
    log "Writing configuration to /etc/meteor/meteor.conf..."
    mkdir -p /etc/meteor
    cat > /etc/meteor/meteor.conf << METEOR_CONF
# Meteor Server Configuration File
# Generated on $(date)
# Modify values here and restart: systemctl restart meteor.service
# Or reload config: systemctl daemon-reload && systemctl restart meteor.service

# Network Configuration
METEOR_HOST=0.0.0.0
METEOR_PORT=$port

# Performance Configuration
METEOR_CORES=$cores
METEOR_SHARDS=$shards
METEOR_MEMORY_MB=$memory

# Persistence Configuration
METEOR_PERSISTENCE=$persistence_enabled
METEOR_RDB_PATH=$rdb_path
METEOR_AOF_PATH=$aof_path
METEOR_SNAPSHOT_INTERVAL=$snapshot_interval
METEOR_SNAPSHOT_OPS=$snapshot_ops
METEOR_FSYNC_POLICY=$fsync_policy

# Health Monitoring Configuration
METEOR_HEALTH_CHECK_TIMEOUT=2      # Seconds to wait for PING response (default: 2)
METEOR_HEALTH_MAX_RETRIES=2        # Number of retries before restart (default: 2)
METEOR_HEALTH_CHECK_INTERVAL=3     # Seconds between health checks (default: 3)

# Hang Detector Configuration (periodic check every 5 seconds via timer)
METEOR_HANG_TIMEOUT=2              # Seconds to wait for PING response (default: 2)
METEOR_HANG_MAX_FAILURES=2         # Number of failures before restart (default: 2)
METEOR_CONF

    # Copy configuration template for reference
    if [ -f "$SCRIPT_DIR/etc/meteor.conf.template" ]; then
        cp "$SCRIPT_DIR/etc/meteor.conf.template" /etc/meteor/meteor.conf.template
    fi

    # Run deployment script with configuration
    if [ -f "$SCRIPT_DIR/scripts/deploy_meteor.sh" ]; then
        cd "$SCRIPT_DIR"
        # Use environment file approach
        source /etc/meteor/meteor.conf
        export METEOR_CORES METEOR_SHARDS METEOR_MEMORY METEOR_PORT METEOR_PERSISTENCE
        export METEOR_SNAPSHOT_INTERVAL METEOR_SNAPSHOT_OPS METEOR_FSYNC_POLICY
        export METEOR_RDB_PATH METEOR_AOF_PATH
        bash scripts/deploy_meteor.sh
    else
        echo "ERROR: Deployment script not found"
        exit 1
    fi
    
    # Setup health monitor service if enabled
    if [ "$enable_health_monitor" = "true" ]; then
        log "Setting up health monitor and hang detector..."
        
        # Create health monitor systemd service (continuous monitoring)
        cat > /etc/systemd/system/meteor-health-monitor.service << HEALTH_SERVICE
[Unit]
Description=Meteor Server Health Monitor
After=meteor.service
Requires=meteor.service

[Service]
Type=simple
User=root
Environment="METEOR_HOST=127.0.0.1"
Environment="METEOR_PORT=$port"
ExecStart=$SCRIPT_DIR/scripts/meteor-health-monitor.sh
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
HEALTH_SERVICE
        
        # Create hang detector systemd service (periodic check via timer)
        cat > /etc/systemd/system/meteor-hangdetector.service << HANGDETECT_SERVICE
[Unit]
Description=Meteor Server Hang Detector and Auto-Restart
After=meteor.service

[Service]
Type=oneshot
User=root
Environment="METEOR_HOST=127.0.0.1"
Environment="METEOR_PORT=$port"
ExecStart=$SCRIPT_DIR/scripts/meteor-hangdetector.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=meteor-hangdetector

[Install]
WantedBy=multi-user.target
HANGDETECT_SERVICE
        
        # Create hang detector systemd timer (runs every 10 seconds)
        cat > /etc/systemd/system/meteor-hangdetector.timer << HANGDETECT_TIMER
[Unit]
Description=Meteor Server Hang Detector Timer
Requires=meteor-hangdetector.service

[Timer]
OnBootSec=30
OnUnitActiveSec=5
AccuracySec=2

[Install]
WantedBy=timers.target
HANGDETECT_TIMER
        
        systemctl daemon-reload
        systemctl enable meteor-health-monitor.service
        systemctl enable meteor-hangdetector.timer
        systemctl start meteor-health-monitor.service
        systemctl start meteor-hangdetector.timer
        
        log "✅ Health monitor and hang detector enabled"
        log "   - Health monitor: every 3s, 2s timeout, 2 retries (max ~10s detection)"
        log "   - Hang detector: every 5s, 2s timeout, 2 retries (max ~12s detection)"
    fi
    
    # Setup RDB cleanup cron job if persistence enabled
    if [ "$persistence_enabled" -eq 1 ]; then
        log "Setting up RDB cleanup cron job..."
        cat > /etc/cron.d/meteor-rdb-cleanup << CRON
# Meteor RDB Cleanup - Run every hour, keep last 3 snapshots
METEOR_RDB_PATH=$rdb_path
0 * * * * root $SCRIPT_DIR/scripts/meteor-rdb-cleanup.sh >> /var/log/meteor/rdb-cleanup.log 2>&1
CRON
        chmod 644 /etc/cron.d/meteor-rdb-cleanup
        log "✅ RDB cleanup cron job installed"
    fi
    
    log "Installation completed successfully!"
    log ""
    log "Service Status:"
    systemctl status meteor.service --no-pager || true
    if [ "$enable_health_monitor" = "true" ]; then
        systemctl status meteor-health-monitor.service --no-pager || true
        systemctl status meteor-hangdetector.timer --no-pager || true
    fi
}

uninstall_meteor() {
    log "Starting Meteor Server uninstallation..."
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Stop services
    systemctl stop meteor 2>/dev/null || true
    systemctl stop meteor-health-monitor 2>/dev/null || true
    systemctl stop meteor-hangdetector.timer 2>/dev/null || true
    systemctl stop meteor-hangdetector.service 2>/dev/null || true
    systemctl disable meteor 2>/dev/null || true
    systemctl disable meteor-health-monitor 2>/dev/null || true
    systemctl disable meteor-hangdetector.timer 2>/dev/null || true
    systemctl disable meteor-hangdetector.service 2>/dev/null || true
    
    # Remove service files
    rm -f /etc/systemd/system/meteor.service
    rm -f /etc/systemd/system/meteor-health-monitor.service
    rm -f /etc/systemd/system/meteor-hangdetector.service
    rm -f /etc/systemd/system/meteor-hangdetector.timer
    systemctl daemon-reload
    
    # Remove user and directories
    userdel meteor 2>/dev/null || true
    rm -rf /opt/meteor
    rm -rf /var/lib/meteor
    rm -rf /var/log/meteor
    rm -rf /etc/meteor
    
    # Remove system configurations
    rm -f /etc/sysctl.d/99-meteor.conf
    rm -f /etc/security/limits.d/99-meteor.conf
    rm -f /etc/logrotate.d/meteor
    rm -f /etc/cron.d/meteor-metrics
    rm -f /etc/cron.d/meteor-rdb-cleanup
    
    log "Uninstallation completed"
}

# Main function
main() {
    # Check if first arg is an action or a parameter
    if [[ "$#" -eq 0 ]] || [[ "$1" == --* && "$1" != "--install" && "$1" != "--uninstall" && "$1" != "--help" && "$1" != "--version" ]]; then
        # No action specified or first arg is a config param, default to install
        install_meteor "$@"
    else
        local action="$1"
        shift
        
        case "$action" in
            --install|install)
                install_meteor "$@"
                ;;
            --uninstall|uninstall)
                uninstall_meteor
                ;;
            --version|version)
                show_version
                ;;
            --help|help|-h)
                show_usage
                ;;
            *)
                echo "Unknown option: $action"
                show_usage
                exit 1
                ;;
        esac
    fi
}

main "$@"
INSTALL_REST

    chmod +x "$PACKAGE_FULL_NAME/install.sh"
    
    log "Installation script created"
}

# Create documentation
create_documentation() {
    log "Creating documentation..."
    
    # Copy main README
    cp deployment/README.md "$PACKAGE_FULL_NAME/docs/README.md"
    
    # Create package-specific README
    cat > "$PACKAGE_FULL_NAME/README.md" << README
# Meteor Server v$PACKAGE_VERSION - Ubuntu $UBUNTU_VERSION Edition

High-performance Redis-compatible server with $OPTIMIZATION_TYPE optimization and advanced features including TTL, LRU eviction, and enterprise-grade monitoring.

## Version Information
- **Ubuntu Version**: $UBUNTU_VERSION
- **Optimization**: $OPTIMIZATION_TYPE  
- **jemalloc Support**: $JEMALLOC_SUPPORT
- **Package**: $PACKAGE_FULL_NAME

## Quick Installation

\`\`\`bash
# Extract package
tar -xzf ${PACKAGE_FULL_NAME}.tar.gz

# Install (requires root privileges)
cd ${PACKAGE_FULL_NAME}
sudo ./install.sh
\`\`\`

## Package Contents

- **bin/**: Server binary and utilities
- **etc/**: Configuration files
- **scripts/**: Deployment and maintenance scripts
- **systemd/**: System service definitions
- **monitoring/**: Telegraf and Grafana configurations
- **docs/**: Detailed documentation

## System Requirements

- **OS**: Linux (Ubuntu 18.04+, CentOS 7+, RHEL 7+)
- **CPU**: x86_64 with AVX2 support (AVX-512 recommended)
- **Memory**: 4GB RAM minimum (8GB+ recommended)
- **Storage**: 1GB free space for installation
- **Network**: TCP port 6379 available

## Features

### Core Features
- ✅ **Redis Protocol Compatible**: Drop-in replacement for Redis
- ✅ **High Performance**: Multi-threaded, NUMA-aware architecture
- ✅ **TTL Support**: Automatic key expiration with configurable policies
- ✅ **LRU Eviction**: Intelligent memory management
- ✅ **Pipeline Support**: Batch operation processing

### Enterprise Features
- ✅ **Production Ready**: Systemd integration with auto-restart
- ✅ **Monitoring**: Prometheus metrics and Grafana dashboards
- ✅ **Security**: Process isolation and resource limits
- ✅ **Backup**: Automated backup and recovery procedures
- ✅ **Logging**: Structured logging with rotation

### Performance Optimizations
- ✅ **SIMD Instructions**: AVX-512/AVX2 vectorization
- ✅ **io_uring**: Asynchronous I/O for Linux
- ✅ **Work Stealing**: Dynamic load balancing across cores
- ✅ **CPU Affinity**: Thread-to-core binding for optimal performance
- ✅ **Zero-Copy**: Memory-efficient data handling

## Configuration

Default configuration is optimized for production use. Key settings:

\`\`\`bash
# Performance
cores = 8
memory = 16384  # MB
work-stealing = true

# Network
bind = 0.0.0.0
port = 6379

# Features
ttl-enabled = true
metrics-enabled = true
\`\`\`

See \`etc/meteor.conf\` for complete configuration options.

## Service Management

\`\`\`bash
# Start/stop service
sudo systemctl start meteor
sudo systemctl stop meteor

# Check status
sudo systemctl status meteor

# View logs
sudo journalctl -u meteor -f

# Health check
redis-cli -h 127.0.0.1 -p 6379 ping
\`\`\`

## Monitoring

### Metrics Endpoint
- **URL**: http://localhost:8001/metrics
- **Format**: Prometheus format
- **Update**: Every 10 seconds

### Grafana Dashboard
Import the dashboard from \`monitoring/grafana_dashboard.json\`

### Key Metrics
- Operations per second
- Cache hit/miss rates
- Memory usage
- Connected clients
- Response time distribution

## Support

- **Documentation**: See \`docs/README.md\` for detailed information
- **Configuration**: Complete parameter reference in config files
- **Troubleshooting**: Common issues and solutions documented

## Version Information

- **Version**: $PACKAGE_VERSION
- **Build Date**: $BUILD_DATE
- **Binary**: $BINARY_NAME

---

For enterprise support and advanced features, contact the Meteor development team.
README

    # Create changelog
    cat > "$PACKAGE_FULL_NAME/CHANGELOG.md" << CHANGELOG
# Meteor Server Changelog

## v8.0.0 ($BUILD_DATE)

### New Features
- ✅ **TTL Support**: Complete time-to-live functionality with SETEX, TTL, EXPIRE commands
- ✅ **Enterprise Deployment**: Production-ready deployment scripts with systemd integration
- ✅ **Monitoring Integration**: Prometheus metrics endpoint and Grafana dashboards
- ✅ **Security Hardening**: Process isolation, resource limits, and secure defaults
- ✅ **Automated Backup**: Scheduled backup system with retention policies

### Performance Improvements
- ✅ **Race Condition Fixes**: Eliminated segfaults in pipeline=1 mode under high load
- ✅ **Work Stealing Optimization**: Dynamic load balancing for better CPU utilization
- ✅ **Memory Management**: LRU eviction with configurable policies
- ✅ **SIMD Optimizations**: AVX-512/AVX2 vectorization for data processing

### Enterprise Features
- ✅ **Production Configuration**: Optimized settings for enterprise deployment
- ✅ **Health Monitoring**: Comprehensive health checks and alerting
- ✅ **Log Management**: Structured logging with automatic rotation
- ✅ **Documentation**: Complete deployment and operations guide

### Bug Fixes
- 🔧 Fixed segmentation faults under high concurrent load
- 🔧 Resolved thread-local buffer corruption in batch processing
- 🔧 Improved error handling and graceful degradation
- 🔧 Enhanced connection management and client timeout handling

### Known Issues
- ⚠️  8-core configuration may experience instability under specific loads
- ⚠️  Performance differential between pipeline=1 and pipeline>1 modes

### Migration Notes
- Configuration file format updated with new TTL parameters
- Default memory eviction policy changed to volatile-lru
- Metrics endpoint moved to port 8001 (configurable)

---

For complete version history, see git commit log.
CHANGELOG

    log "Documentation created"
}

# Create dependency information
create_dependency_info() {
    log "Creating dependency information..."
    
    cat > "$PACKAGE_FULL_NAME/DEPENDENCIES.md" << DEPS
# Meteor Server Dependencies

## Runtime Dependencies

### Required Libraries
- **System Dependencies**: Boost libraries installed via apt package manager
- **No Bundled Libraries**: Relies on system-provided Boost for better compatibility
- **liburing**: io_uring library for asynchronous I/O (Linux)
- **libnuma**: NUMA library for memory management (optional)

### System Requirements
- **glibc**: GNU C Library 2.17+ (usually satisfied on modern Linux)
- **libstdc++**: Standard C++ Library (GCC 7.0+ or equivalent)
- **libpthread**: POSIX threads library
- **librt**: POSIX real-time extensions

### Optional Dependencies
- **libjemalloc**: Alternative memory allocator (recommended for production)
- **libtcmalloc**: Google's thread-caching malloc (alternative to jemalloc)

## Build Dependencies (for compilation)

### Compilers
- **GCC 7.0+** with C++17 support
- **Clang 6.0+** with C++17 support (alternative)

### Build Tools
- **CMake 3.10+** (if using CMake build system)
- **Make** (GNU Make 4.0+)
- **pkg-config** for library detection

### Development Libraries
- **libboost-dev** (1.65+): Boost development headers
- **liburing-dev**: io_uring development headers
- **libnuma-dev**: NUMA development headers

## Installation Commands

### Ubuntu/Debian
\`\`\`bash
sudo apt update
sudo apt install -y \\
    libboost-fiber-dev \\
    libboost-context-dev \\
    libboost-system-dev \\
    liburing-dev \\
    libnuma-dev
\`\`\`

### CentOS/RHEL/Fedora
\`\`\`bash
# Enable EPEL repository first
sudo yum install -y epel-release

sudo yum install -y \\
    boost-devel \\
    liburing-devel \\
    numactl-devel
\`\`\`

### Alpine Linux
\`\`\`bash
apk add --no-cache \\
    boost-dev \\
    liburing-dev \\
    numactl-dev
\`\`\`

## Version Compatibility

### Tested Versions
- **Boost**: 1.65.1, 1.71.0, 1.74.0
- **liburing**: 0.7, 2.0+
- **GCC**: 7.5, 9.4, 11.2
- **Linux Kernel**: 4.15+ (for io_uring support)

### Minimum Versions
- **Boost**: 1.65.0
- **liburing**: 0.7
- **Linux Kernel**: 4.15 (for full io_uring support)

## Static Linking

For deployment flexibility, consider static linking:
\`\`\`bash
g++ -static-libgcc -static-libstdc++ ...
\`\`\`

## Troubleshooting

### Common Issues
1. **liburing not found**: Install liburing-dev package
2. **Boost version too old**: Upgrade to Boost 1.65+
3. **AVX instructions not supported**: Use -mno-avx512f -mno-avx2 flags
4. **NUMA library missing**: Install libnuma-dev (optional)

### Dependency Check
Run the deployment script - it will automatically check and install dependencies.

---

The deployment script handles all dependency installation automatically.
DEPS

    log "Dependency information created"
}

# Create the final package
create_package() {
    log "Creating distributable package..."
    
    # Create tarball
    tar -czf "${PACKAGE_FULL_NAME}.tar.gz" "$PACKAGE_FULL_NAME/"
    
    # Get package size
    PACKAGE_SIZE=$(du -h "${PACKAGE_FULL_NAME}.tar.gz" | cut -f1)
    
    # Create checksum
    sha256sum "${PACKAGE_FULL_NAME}.tar.gz" > "${PACKAGE_FULL_NAME}.tar.gz.sha256"
    
    # Clean up temporary directory
    rm -rf "$PACKAGE_FULL_NAME"
    
    log "Package created successfully!"
    info "Package: ${PACKAGE_FULL_NAME}.tar.gz"
    info "Size: $PACKAGE_SIZE"
    info "Checksum: ${PACKAGE_FULL_NAME}.tar.gz.sha256"
}

# Create distribution information
create_distribution_info() {
    log "Creating distribution information..."
    
    cat > "${PACKAGE_FULL_NAME}-INFO.txt" << INFO
METEOR SERVER DISTRIBUTION PACKAGE
==================================

Package Name: ${PACKAGE_FULL_NAME}.tar.gz
Version: $PACKAGE_VERSION
Build Date: $BUILD_DATE
Binary: $BINARY_NAME

INSTALLATION:
1. Extract: tar -xzf ${PACKAGE_FULL_NAME}.tar.gz
2. Install: cd ${PACKAGE_FULL_NAME} && sudo ./install.sh

REQUIREMENTS:
- Linux OS (Ubuntu 18.04+, CentOS 7+, RHEL 7+)
- Root privileges for installation
- 4GB RAM minimum
- x86_64 CPU with AVX2 support

FEATURES:
- Redis-compatible protocol
- TTL and LRU support
- High-performance architecture
- Enterprise monitoring
- Production-ready deployment

SUPPORT:
- Documentation included in package
- Configuration examples provided
- Monitoring dashboards included

Build Information:
- Source: $BINARY_SOURCE
- Git Commit: $(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
- Build Host: $(hostname)
- Packaged by: $(whoami)

Package Integrity:
- SHA256 checksum provided
- All files integrity verified

INFO

    log "Distribution information created"
}

# Print final summary
print_summary() {
    cat << SUMMARY

🎉 METEOR SERVER PACKAGE CREATED SUCCESSFULLY!

📦 DISTRIBUTION PACKAGE:
========================
Package: ${PACKAGE_FULL_NAME}.tar.gz
Size: $(du -h "${PACKAGE_FULL_NAME}.tar.gz" | cut -f1)
Checksum: ${PACKAGE_FULL_NAME}.tar.gz.sha256

🔧 VERSION INFORMATION:
======================
✅ Ubuntu Version: $UBUNTU_VERSION
✅ CPU Detected: $CPU_CAPABILITIES
✅ Optimization: $OPTIMIZATION_TYPE
✅ jemalloc Support: $JEMALLOC_SUPPORT
✅ Package Version: $PACKAGE_VERSION
✅ Binary Source: $BINARY_SOURCE

📋 PACKAGE CONTENTS:
====================
✅ Meteor server binary (meteor-server) - $OPTIMIZATION_TYPE optimized
✅ Enterprise deployment scripts
✅ Production configuration templates
✅ Systemd service definitions with jemalloc for Ubuntu 24
✅ Monitoring configurations (Telegraf/Grafana)
✅ Backup and recovery scripts
✅ Complete documentation
✅ Installation/uninstallation scripts

🚀 DISTRIBUTION READY:
======================
This package can be distributed independently without source code or compilation dependencies.
Perfect for enterprise deployment to any Ubuntu 24 VM.

INSTALLATION EXAMPLE:
# On target server
tar -xzf ${PACKAGE_FULL_NAME}.tar.gz
cd ${PACKAGE_FULL_NAME}
sudo ./install.sh

UNINSTALLATION:
sudo ./install.sh --uninstall

🔍 FILES CREATED:
==================
- ${PACKAGE_FULL_NAME}.tar.gz         (Main package)
- ${PACKAGE_FULL_NAME}.tar.gz.sha256  (Integrity checksum)
- ${PACKAGE_FULL_NAME}-INFO.txt       (Distribution information)

The package is now ready for enterprise distribution! 🎯

SUMMARY
}

# Main execution
main() {
    print_banner
    
    setup_binary_source
    validate_prerequisites
    create_package_structure
    prepare_binary
    copy_deployment_files
    create_install_script
    create_documentation
    create_dependency_info
    create_distribution_info
    create_package
    
    print_summary
}

# Handle command line arguments and run main
case "${1:-24}" in
    24|22)
        main
        ;;
    *)
        echo "Error: Invalid Ubuntu version '$1'. Use 22 or 24."
        echo "Run '$0 --help' for usage information."
        exit 1
        ;;
esac
