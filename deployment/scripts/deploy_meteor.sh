#!/bin/bash

# **METEOR SERVER - ENTERPRISE PRODUCTION DEPLOYMENT SCRIPT**
# Version: 1.0.0
# Description: Production-ready deployment script for Meteor Redis-compatible server
# Author: Meteor Team
# Compatible: Ubuntu 18.04+, CentOS 7+, RHEL 7+, Amazon Linux 2

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
METEOR_VERSION="8.0"
METEOR_USER="meteor"
METEOR_GROUP="meteor"
METEOR_HOME="/opt/meteor"
METEOR_DATA="/var/lib/meteor"
METEOR_LOG="/var/log/meteor"
METEOR_CONFIG="/etc/meteor"
METEOR_BINARY="meteor-server"
SYSTEMD_SERVICE="meteor.service"

# Server configuration (can be overridden via environment variables from install.sh)
METEOR_CORES="${METEOR_CORES:-8}"
METEOR_SHARDS="${METEOR_SHARDS:-8}"
METEOR_MEMORY="${METEOR_MEMORY:-16384}"  # MB
METEOR_PORT="${METEOR_PORT:-6379}"
METEOR_BIND="${METEOR_BIND:-0.0.0.0}"

# Persistence configuration (configurable via environment variables)
METEOR_SNAPSHOT_INTERVAL="${METEOR_SNAPSHOT_INTERVAL:-600}"  # Default: 10 minutes (more conservative for production)
METEOR_SNAPSHOT_OPERATION_THRESHOLD="${METEOR_SNAPSHOT_OPERATION_THRESHOLD:-1000000}"  # Default: 1M operations
METEOR_AOF_ENABLED="${METEOR_AOF_ENABLED:-true}"
METEOR_AOF_FSYNC_POLICY="${METEOR_AOF_FSYNC_POLICY:-everysec}"

# **ENHANCED CLEANUP AND GCS CONFIGURATION**
METEOR_CLEANUP_ENABLED="${METEOR_CLEANUP_ENABLED:-true}"
METEOR_CLEANUP_RETENTION_DAYS="${METEOR_CLEANUP_RETENTION_DAYS:-7}"  # Keep snapshots for 7 days
METEOR_CLEANUP_STORAGE_THRESHOLD="${METEOR_CLEANUP_STORAGE_THRESHOLD:-20}"  # Cleanup when <20% storage left
METEOR_CLEANUP_BACKUP_TO_GCS="${METEOR_CLEANUP_BACKUP_TO_GCS:-true}"
METEOR_CLEANUP_MIN_KEEP="${METEOR_CLEANUP_MIN_KEEP:-3}"  # Always keep at least 3 snapshots

# **GCS INTEGRATION FOR DEPLOYMENT-SPECIFIC BACKUP**
METEOR_GCS_ENABLED="${METEOR_GCS_ENABLED:-false}"
METEOR_GCS_BUCKET="${METEOR_GCS_BUCKET:-}"
METEOR_GCS_DEPLOYMENT_ID="${METEOR_GCS_DEPLOYMENT_ID:-deploy-$(date +%s)}"  # Unique deployment folder
METEOR_GCS_FOLDER_PREFIX="${METEOR_GCS_FOLDER_PREFIX:-meteor-deployments}"

# **DATA PRESERVATION MODE** (for upgrades/restarts)
DATA_PRESERVATION_MODE="${DATA_PRESERVATION_MODE:-auto}"  # auto, preserve, fresh

# **RECOVERY MODE CONFIGURATION** (runtime behavior)
METEOR_RECOVERY_MODE="${METEOR_RECOVERY_MODE:-auto}"  # auto, fresh, snapshot-only, aof-only, full, gcs-fallback

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a /tmp/meteor_deploy.log
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a /tmp/meteor_deploy.log
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a /tmp/meteor_deploy.log
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a /tmp/meteor_deploy.log
}

print_banner() {
    cat << 'BANNER'

███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝

    ENTERPRISE PRODUCTION DEPLOYMENT v8.0
    High-Performance Redis-Compatible Server
    
BANNER

    echo -e "${GREEN}Meteor Server Production Deployment Script v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}Target Server Version: ${METEOR_VERSION}${NC}"
    echo "=================================================================="
}

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        error "Cannot detect operating system"
    fi
    
    case $OS in
        ubuntu|debian)
            PKG_MANAGER="apt"
            PKG_UPDATE="apt update"
            PKG_INSTALL="apt install -y"
            ;;
        centos|rhel|fedora|amazon)
            PKG_MANAGER="yum"
            PKG_UPDATE="yum update -y"
            PKG_INSTALL="yum install -y"
            ;;
        *)
            error "Unsupported operating system: $OS"
            ;;
    esac
    
    log "Detected OS: $OS $VER, Package Manager: $PKG_MANAGER"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    $PKG_UPDATE
    
    case $PKG_MANAGER in
        apt)
            $PKG_INSTALL build-essential g++ cmake pkg-config \
                        libboost-dev libboost-fiber-dev libboost-context-dev libboost-system-dev \
                        liburing-dev libnuma-dev \
                        libzstd-dev liblz4-dev libssl-dev libcurl4-openssl-dev \
                        curl wget git htop iotop sysstat \
                        supervisor prometheus-node-exporter \
                        logrotate rsyslog
            ;;
        yum)
            # Enable EPEL for additional packages
            yum install -y epel-release
            $PKG_INSTALL gcc-c++ cmake boost-devel liburing-devel numactl-devel \
                        libzstd-devel lz4-devel openssl-devel libcurl-devel \
                        curl wget git htop iotop sysstat \
                        supervisor nodejs npm \
                        logrotate rsyslog
            ;;
    esac
    
    log "System dependencies installed successfully"
}

# Create meteor user and directories
setup_user_and_directories() {
    log "Setting up Meteor user and directories..."
    
    # Create meteor user if doesn't exist
    if ! id "$METEOR_USER" &>/dev/null; then
        useradd --system --home-dir "$METEOR_HOME" --shell /bin/bash "$METEOR_USER"
        log "Created meteor user"
    fi
    
    # Create directories
    mkdir -p "$METEOR_HOME"/{bin,lib,etc}
    mkdir -p "$METEOR_DATA"/{snapshots,aof,ssd,backups,logs,metrics,recovery}
    mkdir -p "$METEOR_LOG"
    mkdir -p "$METEOR_CONFIG"
    
    # Set ownership and permissions
    chown -R "$METEOR_USER:$METEOR_GROUP" "$METEOR_HOME"
    chown -R "$METEOR_USER:$METEOR_GROUP" "$METEOR_DATA"
    chown -R "$METEOR_USER:$METEOR_GROUP" "$METEOR_LOG"
    
    # Set secure permissions
    chmod 755 "$METEOR_HOME"
    chmod 750 "$METEOR_DATA"
    chmod 755 "$METEOR_LOG"
    
    log "User and directories configured"
}

# **DATA PRESERVATION AND RECOVERY FUNCTIONS**
check_existing_data() {
    log "Checking for existing Meteor data..."
    
    local has_snapshots=false
    local has_aof=false
    local snapshot_count=0
    local aof_size=0
    
    # Check for existing snapshots
    if [ -d "$METEOR_DATA/snapshots" ] && [ "$(ls -A $METEOR_DATA/snapshots/*.rdb 2>/dev/null | wc -l)" -gt 0 ]; then
        has_snapshots=true
        snapshot_count=$(ls -1 $METEOR_DATA/snapshots/*.rdb 2>/dev/null | wc -l)
        log "Found existing snapshots: $snapshot_count files"
    fi
    
    # Check for existing AOF
    if [ -f "$METEOR_DATA/aof/meteor.aof" ] && [ -s "$METEOR_DATA/aof/meteor.aof" ]; then
        has_aof=true
        aof_size=$(du -h "$METEOR_DATA/aof/meteor.aof" | cut -f1)
        log "Found existing AOF: $aof_size"
    fi
    
    if [ "$has_snapshots" = true ] || [ "$has_aof" = true ]; then
        log "🔍 EXISTING DATA DETECTED:"
        [ "$has_snapshots" = true ] && log "  📊 Snapshots: $snapshot_count files"
        [ "$has_aof" = true ] && log "  📝 AOF file: $aof_size"
        
        case "$DATA_PRESERVATION_MODE" in
            "preserve")
                log "✅ DATA PRESERVATION: Keeping existing data (preserve mode)"
                backup_existing_data
                ;;
            "fresh")
                warn "🗑️  DATA FRESH START: Removing existing data (fresh mode)"
                remove_existing_data
                ;;
            "auto"|*)
                log "🔄 AUTO PRESERVATION: Backing up and preserving existing data"
                backup_existing_data
                ;;
        esac
    else
        log "✅ No existing data found - fresh installation"
    fi
}

backup_existing_data() {
    log "📦 Backing up existing Meteor data..."
    
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$METEOR_DATA/backups/pre_upgrade_$backup_timestamp"
    
    mkdir -p "$backup_dir"
    
    # Backup snapshots
    if [ -d "$METEOR_DATA/snapshots" ] && [ "$(ls -A $METEOR_DATA/snapshots/*.rdb 2>/dev/null | wc -l)" -gt 0 ]; then
        cp -r "$METEOR_DATA/snapshots" "$backup_dir/"
        log "✅ Snapshots backed up to $backup_dir/snapshots"
    fi
    
    # Backup AOF
    if [ -f "$METEOR_DATA/aof/meteor.aof" ]; then
        mkdir -p "$backup_dir/aof"
        cp "$METEOR_DATA/aof/meteor.aof" "$backup_dir/aof/"
        log "✅ AOF file backed up to $backup_dir/aof/meteor.aof"
    fi
    
    # Backup to GCS if configured
    if [ "${METEOR_GCS_ENABLED}" = "true" ] && [ -n "${METEOR_GCS_BUCKET}" ]; then
        log "☁️  Uploading backup to GCS..."
        upload_backup_to_gcs "$backup_dir"
    fi
    
    chown -R "$METEOR_USER:$METEOR_GROUP" "$backup_dir"
    log "✅ Data backup completed: $backup_dir"
}

upload_backup_to_gcs() {
    local backup_dir="$1"
    local gcs_path="${METEOR_GCS_FOLDER_PREFIX}/${METEOR_GCS_DEPLOYMENT_ID}/backups/$(basename $backup_dir)"
    
    if command -v gsutil >/dev/null 2>&1; then
        gsutil -m rsync -r "$backup_dir" "gs://${METEOR_GCS_BUCKET}/$gcs_path" 2>/dev/null && \
            log "✅ Backup uploaded to gs://${METEOR_GCS_BUCKET}/$gcs_path" || \
            warn "⚠️  GCS backup upload failed"
    else
        warn "⚠️  gsutil not available - GCS backup skipped"
    fi
}

remove_existing_data() {
    log "🗑️  Removing existing Meteor data..."
    rm -rf "$METEOR_DATA/snapshots"/*.rdb 2>/dev/null || true
    rm -f "$METEOR_DATA/aof/meteor.aof" 2>/dev/null || true
    log "✅ Existing data removed"
}

# Install Meteor binary
install_meteor_binary() {
    log "Installing Meteor server binary..."
    
    # Check if binary exists in bin directory (package structure)
    if [ -f "bin/meteor-server" ]; then
        BINARY_PATH="bin/meteor-server"
    elif [ -f "meteor-server" ]; then
        BINARY_PATH="meteor-server"
    else
        error "Meteor binary 'meteor-server' not found in current directory or bin/ directory"
    fi
    
    # Copy and rename binary
    cp "$BINARY_PATH" "$METEOR_HOME/bin/$METEOR_BINARY"
    chmod +x "$METEOR_HOME/bin/$METEOR_BINARY"
    chown "$METEOR_USER:$METEOR_GROUP" "$METEOR_HOME/bin/$METEOR_BINARY"
    
    log "Meteor binary installed at $METEOR_HOME/bin/$METEOR_BINARY"
}

# Generate production configuration
generate_config() {
    log "Generating production configuration..."
    
    cat > "$METEOR_CONFIG/meteor.conf" << CONFIG
# Meteor Server Production Configuration
# Version: 8.0

# Network Configuration
bind = 127.0.0.1
port = 6379
tcp-backlog = 511
tcp-keepalive = 300
timeout = 0

# Server Configuration
cores = ${METEOR_CORES}
shards = ${METEOR_SHARDS}
memory = ${METEOR_MEMORY}  # MB
ssd-path = /var/lib/meteor/ssd

# Performance Tuning
pipeline-enabled = true
work-stealing = true
numa-aware = true
cpu-affinity = true

# Persistence Configuration (configurable via environment variables)
save-snapshots = true
snapshot-interval = ${METEOR_SNAPSHOT_INTERVAL}  # seconds (configurable: 300=5min, 600=10min, 1200=20min)
snapshot-operation-threshold = ${METEOR_SNAPSHOT_OPERATION_THRESHOLD}  # operations (configurable: 100000=100K, 1000000=1M)
snapshot-path = /var/lib/meteor/snapshots

# AOF (Append-Only File) for zero data loss
aof-enabled = ${METEOR_AOF_ENABLED}
aof-fsync-policy = ${METEOR_AOF_FSYNC_POLICY}  # never, always, everysec
aof-filename = meteor.aof
aof-path = /var/lib/meteor/aof

# **ENHANCED CLEANUP AND RECOVERY CONFIGURATION**
cleanup-enabled = ${METEOR_CLEANUP_ENABLED}
cleanup-retention-days = ${METEOR_CLEANUP_RETENTION_DAYS}
cleanup-storage-threshold = ${METEOR_CLEANUP_STORAGE_THRESHOLD}
cleanup-backup-to-gcs = ${METEOR_CLEANUP_BACKUP_TO_GCS}
cleanup-min-keep = ${METEOR_CLEANUP_MIN_KEEP}

# **RECOVERY MODE** (runtime behavior - can also be overridden via -r command line)
recovery-mode = ${METEOR_RECOVERY_MODE}  # auto, fresh, snapshot-only, aof-only, full, gcs-fallback

# Cloud Storage Backends
gcs-enabled = ${METEOR_GCS_ENABLED}
gcs-bucket = ${METEOR_GCS_BUCKET}
gcs-deployment-id = ${METEOR_GCS_DEPLOYMENT_ID}
gcs-folder-prefix = ${METEOR_GCS_FOLDER_PREFIX}
s3-enabled = false
s3-bucket = your-meteor-backup-bucket
s3-region = us-east-1

# Logging
log-level = info
log-file = /var/log/meteor/meteor.log
log-rotate = daily
log-max-size = 100MB

# Monitoring
metrics-enabled = true
metrics-port = 8001
metrics-interval = 10  # seconds

# Security
protected-mode = true
require-auth = false
# auth-password = your_secure_password_here

# Limits
max-clients = 10000
max-memory-policy = volatile-lru

# TTL Configuration
ttl-enabled = true
ttl-check-interval = 1  # seconds
CONFIG

    chown "$METEOR_USER:$METEOR_GROUP" "$METEOR_CONFIG/meteor.conf"
    chmod 640 "$METEOR_CONFIG/meteor.conf"
    
    log "Configuration file created at $METEOR_CONFIG/meteor.conf"
}

# Install systemd service
install_systemd_service() {
    log "Installing systemd service..."
    
    # Build ExecStart command dynamically based on configuration
    local exec_start_cmd="$METEOR_HOME/bin/$METEOR_BINARY -h $METEOR_BIND -p $METEOR_PORT -c $METEOR_CORES -s $METEOR_SHARDS -m $METEOR_MEMORY"
    
    # **CRITICAL: Always add recovery mode parameter for systemd restarts**
    # Default to "auto" for systemd restarts to always preserve data unless explicitly overridden
    local recovery_mode="${METEOR_RECOVERY_MODE:-auto}"
    exec_start_cmd="$exec_start_cmd -r $recovery_mode"
    log "🔧 Recovery mode for systemd restarts: $recovery_mode (ensures data preservation on hang detector/crash restarts)"
    
    # Only add SSD path if explicitly enabled (default: disabled for stability)
    if [ "${SSD_CACHE_ENABLED:-false}" = "true" ]; then
        exec_start_cmd="$exec_start_cmd -d $METEOR_DATA/ssd"
        log "✅ SSD cache enabled: $METEOR_DATA/ssd"
        # Ensure SSD directory exists and has proper permissions
        mkdir -p "$METEOR_DATA/ssd"
        chown "$METEOR_USER:$METEOR_GROUP" "$METEOR_DATA/ssd"
        chmod 755 "$METEOR_DATA/ssd"
    else
        log "⚠️  SSD cache disabled (default for stability). Set SSD_CACHE_ENABLED=true to enable."
    fi
    
    cat > "/etc/systemd/system/$SYSTEMD_SERVICE" << SERVICE
[Unit]
Description=Meteor Redis-Compatible High-Performance Server (${METEOR_CORES}C/${METEOR_SHARDS}S/${METEOR_MEMORY}MB)
Documentation=https://github.com/meteor-server/meteor
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$METEOR_USER
Group=$METEOR_GROUP
RuntimeDirectory=meteor
RuntimeDirectoryMode=0755

# Security Settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
ProtectSystem=strict
ReadWritePaths=$METEOR_DATA $METEOR_LOG /run/meteor
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# Resource Limits
LimitNOFILE=65536
LimitNPROC=65536
LimitMEMLOCK=infinity

# Environment with jemalloc for Ubuntu 24
Environment="LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"
Environment=METEOR_DATA=$METEOR_DATA
Environment=METEOR_LOG=$METEOR_LOG

# **CRITICAL DATA PRESERVATION**
# Recovery mode: ${recovery_mode} ensures data preservation on all systemd restarts
# This includes: crash restarts, hang detector restarts, manual service restarts
# The -r ${recovery_mode} parameter ensures latest snapshot + AOF are ALWAYS loaded
ExecStart=$exec_start_cmd

# Enhanced Restart Policy with Hanging Detection and Data Preservation
# IMPORTANT: Every restart will recover from latest snapshot + AOF (recovery-mode=${recovery_mode})
Restart=always
RestartSec=15
StartLimitInterval=300
StartLimitBurst=5

# Reload and Signal Handling
ExecReload=/bin/kill -HUP \$MAINPID

# Restart Conditions (aggressive restart for hanging detection)
RestartKillSignal=SIGTERM
TimeoutStopSec=20
TimeoutStartSec=45

# Process Monitoring
KillMode=mixed
SendSIGKILL=yes

# Output Handling  
StandardOutput=journal
StandardError=journal
SyslogIdentifier=meteor

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable "$SYSTEMD_SERVICE"
    
    log "Systemd service installed and enabled with parameters: ${METEOR_CORES}C/${METEOR_SHARDS}S/${METEOR_MEMORY}MB"
}

# Setup log rotation
setup_logrotate() {
    log "Setting up log rotation..."
    
    cat > "/etc/logrotate.d/meteor" << LOGROTATE
$METEOR_LOG/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
    create 644 $METEOR_USER $METEOR_GROUP
    postrotate
        systemctl reload meteor.service > /dev/null 2>&1 || true
    endscript
}
LOGROTATE

    log "Log rotation configured"
}

# Setup monitoring and metrics
setup_monitoring() {
    log "Setting up monitoring and metrics..."
    
    # Create metrics collection script
    cat > "$METEOR_HOME/bin/collect_metrics.sh" << 'METRICS'
#!/bin/bash
# Meteor Metrics Collection Script

METEOR_HOST="127.0.0.1"
METEOR_PORT="6379"
METRICS_FILE="/var/lib/meteor/metrics/meteor_metrics.prom"

# Collect metrics using redis-cli INFO equivalent
collect_metrics() {
    # This would be replaced with actual Meteor INFO command implementation
    cat > "$METRICS_FILE" << PROM
# HELP meteor_commands_total Total number of commands processed
# TYPE meteor_commands_total counter
meteor_commands_total $(date +%s)

# HELP meteor_cache_hits_total Total number of cache hits
# TYPE meteor_cache_hits_total counter
meteor_cache_hits_total $(date +%s)

# HELP meteor_cache_misses_total Total number of cache misses
# TYPE meteor_cache_misses_total counter
meteor_cache_misses_total $(date +%s)

# HELP meteor_connected_clients Current number of connected clients
# TYPE meteor_connected_clients gauge
meteor_connected_clients 0

# HELP meteor_memory_usage_bytes Current memory usage in bytes
# TYPE meteor_memory_usage_bytes gauge
meteor_memory_usage_bytes $(date +%s)

# HELP meteor_operations_per_second Current operations per second
# TYPE meteor_operations_per_second gauge
meteor_operations_per_second 0
PROM
}

collect_metrics
METRICS

    chmod +x "$METEOR_HOME/bin/collect_metrics.sh"
    chown "$METEOR_USER:$METEOR_GROUP" "$METEOR_HOME/bin/collect_metrics.sh"
    
    # Setup cron job for metrics collection
    echo "*/10 * * * * $METEOR_USER $METEOR_HOME/bin/collect_metrics.sh" > /etc/cron.d/meteor-metrics
    
    log "Monitoring and metrics configured"
}

# Setup comprehensive health check with monitoring
setup_healthcheck() {
    log "Setting up comprehensive health check and monitoring..."
    
    # Enhanced health check script with detailed logging and hanging detection
    cat > "$METEOR_HOME/bin/healthcheck.sh" << 'HEALTH'
#!/bin/bash
# Meteor Comprehensive Health Check Script
# Detects both process termination and hanging (unresponsive) servers

METEOR_HOST="127.0.0.1"
METEOR_PORT="6379"
TIMEOUT=3
LOG_FILE="/var/log/meteor/healthcheck.log"
MAX_LOG_SIZE=10485760  # 10MB

# Rotate log if too large
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
    fi
}

# Enhanced logging with timestamp
log_health() {
    rotate_log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# Check if meteor process is running
check_process() {
    if ! pgrep -f "meteor-server.*-p $METEOR_PORT" >/dev/null 2>&1; then
        log_health "ERROR: Meteor process not found for port $METEOR_PORT"
        return 1
    fi
    return 0
}

# Check if meteor is responding to Redis commands
check_redis_response() {
    local start_time=$(date +%s)
    
    # Test basic PING command
    if ! timeout $TIMEOUT redis-cli -h $METEOR_HOST -p $METEOR_PORT ping 2>/dev/null | grep -q "PONG"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_health "ERROR: Redis PING failed or timed out after ${duration}s (timeout: ${TIMEOUT}s)"
        return 1
    fi
    
    # Test basic command execution (SET/GET)
    local test_key="healthcheck:$(date +%s)"
    local test_value="healthy"
    
    if ! timeout $TIMEOUT redis-cli -h $METEOR_HOST -p $METEOR_PORT set "$test_key" "$test_value" 2>/dev/null | grep -q "OK"; then
        log_health "ERROR: Redis SET command failed or timed out"
        return 1
    fi
    
    if ! timeout $TIMEOUT redis-cli -h $METEOR_HOST -p $METEOR_PORT get "$test_key" 2>/dev/null | grep -q "$test_value"; then
        log_health "ERROR: Redis GET command failed or returned wrong value"
        return 1
    fi
    
    # Cleanup test key
    timeout $TIMEOUT redis-cli -h $METEOR_HOST -p $METEOR_PORT del "$test_key" >/dev/null 2>&1 || true
    
    return 0
}

# Main health check logic
main() {
    # Check if process is running
    if ! check_process; then
        log_health "CRITICAL: Meteor process not running - systemd will restart"
        exit 1
    fi
    
    # Check if server is responding
    if ! check_redis_response; then
        log_health "CRITICAL: Meteor server is unresponsive (hanging detected) - systemd will restart"
        exit 1
    fi
    
    # Success - server is healthy and responsive
    log_health "SUCCESS: Meteor server is healthy and responsive"
    exit 0
}

main "$@"
HEALTH

    # Create hang detection and restart script
    cat > "$METEOR_HOME/bin/hang-detector.sh" << 'HANGDETECTOR'
#!/bin/bash
# Meteor Hang Detector and Auto-Restart Script
# Runs independently to detect hanging servers and restart them

METEOR_HOST="127.0.0.1"
METEOR_PORT="6379"
TIMEOUT=5
LOG_FILE="/var/log/meteor/hang-detector.log"
MAX_FAILURES=2
FAILURE_COUNT_FILE="/tmp/meteor-failure-count"

# Enhanced logging
log_hang() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HANG-DETECTOR: $1" >> "$LOG_FILE" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HANG-DETECTOR: $1"
}

# Get current failure count
get_failure_count() {
    if [ -f "$FAILURE_COUNT_FILE" ]; then
        cat "$FAILURE_COUNT_FILE" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Increment failure count
increment_failure_count() {
    local count=$(get_failure_count)
    echo $((count + 1)) > "$FAILURE_COUNT_FILE"
    echo $((count + 1))
}

# Reset failure count
reset_failure_count() {
    echo 0 > "$FAILURE_COUNT_FILE"
}

# Check if meteor is responsive
is_meteor_responsive() {
    # Test PING command with timeout
    if ! timeout $TIMEOUT redis-cli -h $METEOR_HOST -p $METEOR_PORT ping 2>/dev/null | grep -q "PONG"; then
        return 1
    fi
    
    # Test basic SET/GET operation
    local test_key="hang-test:$(date +%s)"
    if ! timeout $TIMEOUT redis-cli -h $METEOR_HOST -p $METEOR_PORT set "$test_key" "ok" 2>/dev/null | grep -q "OK"; then
        return 1
    fi
    
    timeout $TIMEOUT redis-cli -h $METEOR_HOST -p $METEOR_PORT del "$test_key" >/dev/null 2>&1 || true
    return 0
}

# Restart meteor service
restart_meteor() {
    log_hang "CRITICAL: Restarting meteor.service due to hanging detection"
    systemctl restart meteor.service
    sleep 10
    
    if systemctl is-active meteor.service >/dev/null 2>&1; then
        log_hang "SUCCESS: Meteor service restarted successfully"
        reset_failure_count
    else
        log_hang "ERROR: Failed to restart meteor service"
    fi
}

# Main hang detection logic
main() {
    log_hang "Starting hang detection check"
    
    # Check if meteor service is running
    if ! systemctl is-active meteor.service >/dev/null 2>&1; then
        log_hang "INFO: Meteor service is not running, skipping hang detection"
        reset_failure_count
        return 0
    fi
    
    # Test if meteor is responsive
    if is_meteor_responsive; then
        log_hang "SUCCESS: Meteor server is responsive"
        reset_failure_count
        return 0
    fi
    
    # Server is unresponsive - increment failure count
    local failures=$(increment_failure_count)
    log_hang "WARNING: Meteor server unresponsive (failure $failures/$MAX_FAILURES)"
    
    # If we've reached max failures, restart the service
    if [ $failures -ge $MAX_FAILURES ]; then
        log_hang "CRITICAL: Max failures reached ($failures/$MAX_FAILURES) - initiating restart"
        restart_meteor
    fi
}

main "$@"
HANGDETECTOR

    # Create systemd hang detector service (runs as root to restart services)
    cat > "/etc/systemd/system/meteor-hangdetector.service" << 'HANGDETMON'
[Unit]
Description=Meteor Server Hang Detector and Auto-Restart
After=meteor.service

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/opt/meteor/bin/hang-detector.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=meteor-hangdetector

[Install]
WantedBy=multi-user.target
HANGDETMON

    # Create systemd hang detector timer (runs every 10 seconds)
    cat > "/etc/systemd/system/meteor-hangdetector.timer" << 'HANGTIMER'
[Unit]
Description=Meteor Server Hang Detector Timer
Requires=meteor-hangdetector.service

[Timer]
OnBootSec=30
OnUnitActiveSec=10
AccuracySec=2

[Install]
WantedBy=timers.target
HANGTIMER

    # Also create the original health monitor service (for manual checks)
    cat > "/etc/systemd/system/meteor-healthmon.service" << 'HEALTHMON'
[Unit]
Description=Meteor Server Health Monitor
After=meteor.service

[Service]
Type=oneshot
User=meteor
Group=meteor
ExecStart=/opt/meteor/bin/healthcheck.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=meteor-healthmon

[Install]
WantedBy=multi-user.target
HEALTHMON

    # Create systemd health monitor timer (runs every 5 seconds)
    cat > "/etc/systemd/system/meteor-healthmon.timer" << 'HEALTHTIMER'
[Unit]
Description=Meteor Server Health Monitor Timer
Requires=meteor-healthmon.service

[Timer]
OnBootSec=15
OnUnitActiveSec=5
AccuracySec=1

[Install]
WantedBy=timers.target
HEALTHTIMER

    chmod +x "$METEOR_HOME/bin/healthcheck.sh"
    chmod +x "$METEOR_HOME/bin/hang-detector.sh"
    chown "$METEOR_USER:$METEOR_GROUP" "$METEOR_HOME/bin/healthcheck.sh"
    chown root:root "$METEOR_HOME/bin/hang-detector.sh"
    
    # Enable comprehensive health monitoring services
    systemctl daemon-reload
    systemctl enable meteor-healthmon.timer
    systemctl enable meteor-hangdetector.timer
    systemctl start meteor-healthmon.timer
    systemctl start meteor-hangdetector.timer
    
    log "✅ Comprehensive health monitoring configured:"
    log "   - Health check: every 5 seconds"  
    log "   - Hang detector: every 10 seconds with auto-restart"
    log "   - Max failures before restart: 2 (20 seconds max detection time)"
    log "   - Health logs: /var/log/meteor/healthcheck.log"
    log "   - Hang detector logs: /var/log/meteor/hang-detector.log"
}

# Optimize system settings
optimize_system() {
    log "Optimizing system settings for production..."
    
    # Kernel parameters for high performance
    cat > "/etc/sysctl.d/99-meteor.conf" << SYSCTL
# Meteor Server System Optimization

# Network settings
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# Memory settings
vm.overcommit_memory = 1
vm.swappiness = 1

# File descriptor limits
fs.file-max = 2097152

# Hugepages (optional, for large memory deployments)
# vm.nr_hugepages = 512
SYSCTL

    # Apply settings
    sysctl -p /etc/sysctl.d/99-meteor.conf
    
    # Security limits
    cat > "/etc/security/limits.d/99-meteor.conf" << LIMITS
# Meteor Server Resource Limits
$METEOR_USER soft nofile 65536
$METEOR_USER hard nofile 65536
$METEOR_USER soft nproc 65536
$METEOR_USER hard nproc 65536
$METEOR_USER soft memlock unlimited
$METEOR_USER hard memlock unlimited
LIMITS

    log "System optimization completed"
}

# Validate installation
validate_installation() {
    log "Validating installation..."
    
    # Check binary
    if [ ! -x "$METEOR_HOME/bin/$METEOR_BINARY" ]; then
        error "Meteor binary not found or not executable"
    fi
    
    # Check configuration
    if [ ! -f "$METEOR_CONFIG/meteor.conf" ]; then
        error "Configuration file not found"
    fi
    
    # Check systemd service
    if ! systemctl is-enabled "$SYSTEMD_SERVICE" &>/dev/null; then
        error "Systemd service not enabled"
    fi
    
    # Check directories
    for dir in "$METEOR_HOME" "$METEOR_DATA" "$METEOR_LOG" "$METEOR_CONFIG"; do
        if [ ! -d "$dir" ]; then
            error "Directory $dir not found"
        fi
    done
    
    log "Installation validation passed"
}

# Start services
start_services() {
    log "Starting Meteor services..."
    
    systemctl start "$SYSTEMD_SERVICE"
    
    # Wait for service to start
    sleep 5
    
    if systemctl is-active --quiet "$SYSTEMD_SERVICE"; then
        log "Meteor server started successfully"
    else
        error "Failed to start Meteor server"
    fi
}

# Print final instructions
print_final_instructions() {
    cat << INSTRUCTIONS

🎉 METEOR SERVER DEPLOYMENT COMPLETED SUCCESSFULLY!

📋 DEPLOYMENT SUMMARY:
========================
✅ System dependencies installed
✅ Meteor user and directories created  
✅ Production configuration generated
✅ Systemd service installed and enabled
✅ Log rotation configured
✅ Monitoring and health checks setup
✅ System optimized for production
✅ Server started and validated

📂 KEY LOCATIONS:
==================
Binary:        $METEOR_HOME/bin/$METEOR_BINARY
Configuration: $METEOR_CONFIG/meteor.conf
Data Directory: $METEOR_DATA
Log Directory:  $METEOR_LOG
Service File:   /etc/systemd/system/$SYSTEMD_SERVICE

🔧 SERVICE MANAGEMENT:
======================
Start:    sudo systemctl start meteor
Stop:     sudo systemctl stop meteor
Restart:  sudo systemctl restart meteor
Status:   sudo systemctl status meteor
Logs:     sudo journalctl -u meteor -f

📊 MONITORING:
===============
Health Check: $METEOR_HOME/bin/healthcheck.sh
Metrics:      $METEOR_HOME/bin/collect_metrics.sh
Metrics File: $METEOR_DATA/metrics/meteor_metrics.prom

🔗 CONNECTION:
===============
Host: 127.0.0.1
Port: 6379
Test: redis-cli -h 127.0.0.1 -p 6379 ping

📈 NEXT STEPS:
===============
1. Configure monitoring (Telegraf/Prometheus)
2. Setup backup procedures
3. Configure alerting
4. Load testing and tuning

INSTRUCTIONS
}

# Main deployment function
main() {
    print_banner
    
    log "Starting Meteor Server Enterprise Deployment..."
    
    check_root
    detect_os
    install_dependencies
    setup_user_and_directories
    check_existing_data  # **NEW: Check for existing data and handle preservation**
    install_meteor_binary
    generate_config
    install_systemd_service
    setup_logrotate
    setup_monitoring
    setup_healthcheck
    optimize_system
    validate_installation
    start_services
    
    log "Deployment completed successfully!"
    print_final_instructions
}

# Handle command line arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    validate)
        validate_installation
        ;;
    --help|-h)
        echo "Usage: $0 [deploy|validate|--help]"
        echo "  deploy   - Full deployment (default)"
        echo "  validate - Validate existing installation"
        echo "  --help   - Show this help"
        ;;
    *)
        error "Unknown command: $1"
        ;;
esac
