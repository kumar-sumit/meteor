#!/bin/bash

# GCP Deployment and Benchmark Script
# Deploys Meteor, Redis, and Dragonfly on GCP VM and runs heavy load benchmarks

set -e

# Configuration
GCP_PROJECT=${GCP_PROJECT:-"your-project-id"}
GCP_ZONE=${GCP_ZONE:-"us-central1-a"}
GCP_INSTANCE_NAME=${GCP_INSTANCE_NAME:-"meteor-benchmark-vm"}
GCP_MACHINE_TYPE=${GCP_MACHINE_TYPE:-"n1-standard-8"}  # 8 vCPUs, 30GB RAM
GCP_DISK_SIZE=${GCP_DISK_SIZE:-"100GB"}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to create GCP VM
create_gcp_vm() {
    log "Creating GCP VM instance..."
    
    gcloud compute instances create $GCP_INSTANCE_NAME \
        --project=$GCP_PROJECT \
        --zone=$GCP_ZONE \
        --machine-type=$GCP_MACHINE_TYPE \
        --network-interface=network-tier=PREMIUM,subnet=default \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --service-account=default \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --create-disk=auto-delete=yes,boot=yes,device-name=$GCP_INSTANCE_NAME,image=projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-v20231213,mode=rw,size=$GCP_DISK_SIZE,type=projects/$GCP_PROJECT/zones/$GCP_ZONE/diskTypes/pd-standard \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=purpose=benchmark,type=meteor-testing \
        --reservation-affinity=any
    
    log "Waiting for VM to be ready..."
    sleep 30
}

# Function to get VM external IP
get_vm_ip() {
    gcloud compute instances describe $GCP_INSTANCE_NAME \
        --project=$GCP_PROJECT \
        --zone=$GCP_ZONE \
        --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
}

# Function to setup environment on GCP VM
setup_gcp_environment() {
    local vm_ip=$1
    
    log "Setting up environment on GCP VM ($vm_ip)..."
    
    # Create setup script
    cat > setup_vm.sh << 'EOF'
#!/bin/bash
set -e

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

# Install dependencies
sudo apt-get install -y \
    build-essential \
    clang \
    golang-go \
    git \
    redis-server \
    redis-tools \
    wget \
    curl \
    htop \
    iotop \
    sysstat \
    lsof \
    netcat

# Install Go 1.21+ if needed
if ! go version | grep -q "go1.2[1-9]"; then
    cd /tmp
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin
fi

# Install Dragonfly
cd /tmp
wget https://github.com/dragonflydb/dragonfly/releases/download/v1.15.1/dragonfly-x86_64.tar.gz
tar -xzf dragonfly-x86_64.tar.gz
sudo mv dragonfly-x86_64 /usr/local/bin/dragonfly
sudo chmod +x /usr/local/bin/dragonfly

# Configure Redis for high performance
sudo tee /etc/redis/redis.conf > /dev/null << 'REDIS_CONF'
bind 127.0.0.1
port 6379
timeout 0
tcp-keepalive 300
daemonize yes
supervised no
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
save ""
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory 2gb
maxmemory-policy allkeys-lru
maxmemory-samples 5
appendonly no
tcp-backlog 511
tcp-keepalive 300
timeout 0
REDIS_CONF

# System optimizations for high performance
sudo tee -a /etc/sysctl.conf > /dev/null << 'SYSCTL_CONF'
# Network optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1

# Memory optimizations
vm.swappiness = 1
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.overcommit_memory = 1

# File descriptor limits
fs.file-max = 2097152
SYSCTL_CONF

sudo sysctl -p

# Set ulimits
sudo tee /etc/security/limits.conf > /dev/null << 'LIMITS_CONF'
* soft nofile 1000000
* hard nofile 1000000
* soft nproc 1000000
* hard nproc 1000000
root soft nofile 1000000
root hard nofile 1000000
root soft nproc 1000000
root hard nproc 1000000
LIMITS_CONF

# Create benchmark directory
mkdir -p ~/meteor-benchmark
cd ~/meteor-benchmark

echo "Environment setup completed successfully!"
EOF

    # Copy and execute setup script
    scp setup_vm.sh $vm_ip:~/
    ssh $vm_ip 'chmod +x ~/setup_vm.sh && ~/setup_vm.sh'
    
    log "Environment setup completed"
}

# Function to deploy code to GCP VM
deploy_code_to_gcp() {
    local vm_ip=$1
    
    log "Deploying code to GCP VM..."
    
    # Create deployment package
    local deploy_dir="meteor-gcp-deployment"
    mkdir -p $deploy_dir
    
    # Copy essential files
    cp -r cmd/ $deploy_dir/
    cp -r pkg/ $deploy_dir/
    cp -r scripts/ $deploy_dir/
    cp go.mod go.sum $deploy_dir/
    cp meteor-sharded-server-v2 $deploy_dir/ 2>/dev/null || true
    cp meteor-sharded-server-tiered $deploy_dir/ 2>/dev/null || true
    
    # Create build script for GCP
    cat > $deploy_dir/build_on_gcp.sh << 'EOF'
#!/bin/bash
set -e

export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go

# Build Meteor servers
echo "Building Meteor servers..."
go build -o meteor-sharded-server-v2 ./cmd/server-sharded/
go build -o meteor-sharded-server-tiered ./cmd/server-sharded/

# Make scripts executable
chmod +x scripts/*.sh

echo "Build completed successfully!"
EOF

    chmod +x $deploy_dir/build_on_gcp.sh
    
    # Deploy to GCP VM
    scp -r $deploy_dir $vm_ip:~/meteor-benchmark/
    ssh $vm_ip 'cd ~/meteor-benchmark/meteor-gcp-deployment && ./build_on_gcp.sh'
    
    # Cleanup local deployment directory
    rm -rf $deploy_dir
    
    log "Code deployment completed"
}

# Function to run benchmarks on GCP VM
run_gcp_benchmarks() {
    local vm_ip=$1
    
    log "Running benchmarks on GCP VM..."
    
    # Create remote benchmark script
    cat > run_remote_benchmark.sh << 'EOF'
#!/bin/bash
set -e

cd ~/meteor-benchmark/meteor-gcp-deployment

# Stop any existing servers
sudo pkill -f redis-server || true
sudo pkill -f dragonfly || true
sudo pkill -f meteor-sharded-server || true

# Wait for ports to be free
sleep 5

# Run the heavy load benchmark
echo "Starting heavy load benchmark..."
./scripts/gcp_heavy_load_benchmark.sh

# Collect system information
echo "Collecting system information..."
mkdir -p benchmark_results_*/system_info

# CPU info
cat /proc/cpuinfo > benchmark_results_*/system_info/cpuinfo.txt

# Memory info
free -h > benchmark_results_*/system_info/memory.txt
cat /proc/meminfo > benchmark_results_*/system_info/meminfo.txt

# Disk info
df -h > benchmark_results_*/system_info/disk.txt

# Network info
ss -tuln > benchmark_results_*/system_info/network.txt

# System limits
ulimit -a > benchmark_results_*/system_info/limits.txt

# Kernel parameters
sysctl -a > benchmark_results_*/system_info/sysctl.txt 2>/dev/null || true

echo "Benchmark completed!"
EOF

    # Execute remote benchmark
    scp run_remote_benchmark.sh $vm_ip:~/
    ssh $vm_ip 'chmod +x ~/run_remote_benchmark.sh && ~/run_remote_benchmark.sh'
    
    # Download results
    local results_dir="gcp_benchmark_results_$(date +%Y%m%d_%H%M%S)"
    mkdir -p $results_dir
    
    scp -r $vm_ip:~/meteor-benchmark/meteor-gcp-deployment/benchmark_results_* $results_dir/
    
    log "Benchmark results downloaded to: $results_dir"
    
    # Cleanup remote script
    rm run_remote_benchmark.sh
    
    return 0
}

# Function to analyze results
analyze_results() {
    local results_dir=$1
    
    log "Analyzing benchmark results..."
    
    # Find the latest results directory
    local latest_results=$(find $results_dir -name "benchmark_results_*" -type d | sort | tail -1)
    
    if [ -z "$latest_results" ]; then
        log "No benchmark results found"
        return 1
    fi
    
    log "Latest results: $latest_results"
    
    # Display crash summary
    if [ -f "$latest_results/crash_summary.csv" ]; then
        log "Crash Summary:"
        cat "$latest_results/crash_summary.csv"
    fi
    
    # Display performance summary
    log "Performance Summary:"
    for server in redis dragonfly meteor-v2 meteor-tiered; do
        local best_result=$(find "$latest_results" -name "${server}_*.txt" -exec grep "SET" {} \; 2>/dev/null | cut -d',' -f2 | sort -nr | head -1)
        if [ -n "$best_result" ]; then
            log "  $server: $best_result ops/sec"
        else
            log "  $server: No results (crashed or failed)"
        fi
    done
    
    # Check for crashes
    local crashed_servers=$(grep -v "Server,Crashes" "$latest_results/crash_summary.csv" | grep -v ",0$" | cut -d',' -f1)
    if [ -n "$crashed_servers" ]; then
        log "SERVERS WITH CRASHES:"
        echo "$crashed_servers"
    else
        log "✅ No crashes detected in any server!"
    fi
    
    return 0
}

# Function to cleanup GCP resources
cleanup_gcp() {
    log "Cleaning up GCP resources..."
    
    gcloud compute instances delete $GCP_INSTANCE_NAME \
        --project=$GCP_PROJECT \
        --zone=$GCP_ZONE \
        --quiet || true
    
    log "GCP cleanup completed"
}

# Main function
main() {
    local action=${1:-"full"}
    
    case $action in
        "create")
            create_gcp_vm
            ;;
        "setup")
            local vm_ip=$(get_vm_ip)
            setup_gcp_environment $vm_ip
            ;;
        "deploy")
            local vm_ip=$(get_vm_ip)
            deploy_code_to_gcp $vm_ip
            ;;
        "benchmark")
            local vm_ip=$(get_vm_ip)
            run_gcp_benchmarks $vm_ip
            ;;
        "cleanup")
            cleanup_gcp
            ;;
        "full")
            log "Running full GCP benchmark pipeline..."
            
            # Create VM
            create_gcp_vm
            
            # Get VM IP
            local vm_ip=$(get_vm_ip)
            log "VM IP: $vm_ip"
            
            # Setup environment
            setup_gcp_environment $vm_ip
            
            # Deploy code
            deploy_code_to_gcp $vm_ip
            
            # Run benchmarks
            run_gcp_benchmarks $vm_ip
            
            # Analyze results
            analyze_results "gcp_benchmark_results_$(date +%Y%m%d_%H%M%S)"
            
            # Cleanup (optional - comment out to keep VM for investigation)
            # cleanup_gcp
            
            log "Full benchmark pipeline completed!"
            ;;
        *)
            echo "Usage: $0 [create|setup|deploy|benchmark|cleanup|full]"
            echo "  create    - Create GCP VM"
            echo "  setup     - Setup environment on existing VM"
            echo "  deploy    - Deploy code to existing VM"
            echo "  benchmark - Run benchmarks on existing VM"
            echo "  cleanup   - Delete GCP VM"
            echo "  full      - Run complete pipeline (default)"
            exit 1
            ;;
    esac
}

# Set up signal handlers for cleanup
trap cleanup_gcp EXIT

# Run main function
main "$@" 