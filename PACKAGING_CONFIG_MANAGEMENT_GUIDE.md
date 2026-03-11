# Meteor Packaging & Configuration Management - Complete Guide

## ✅ **COMPLETE: Enhanced Package Script with Runtime Configuration Management**

The `create_meteor_package.sh` script has been fully enhanced with:
1. **Flexible Binary/Source Selection** (--binary and --source-file parameters)
2. **Runtime Configuration Management** (meteor.conf with dynamic updates)
3. **Service Restart via Configuration Changes** (no reinstallation needed)

---

## 🎯 **Key Features**

### 1. **Binary Selection Priority** ✅

**Command-Line Parameters**:
```bash
./create_meteor_package.sh --binary <PATH>           # Use existing binary
./create_meteor_package.sh --source-file <PATH>      # Build from specific source
./create_meteor_package.sh                           # Auto-detect (default)
```

**Auto-Detection Priority** (when no params specified):
1. Pre-built: `meteor-server-v8.3-production-configurable`
2. Pre-built: `meteor-server-ubuntu24-avx512`
3. **Source: `cpp/meteor_redis_client_compatible_with_persistence.cpp`** ← **Highest Priority**
4. Source: `cpp/meteor_baseline_mget_single_cmd_optimized.cpp`
5. Source: `cpp/meteor_baseline_prod_v4.cpp`
6. Other fallbacks...

**Build Configuration**:
- Compiler: `g++-13` (C++20) or `g++` (fallback)
- Optimization: `-O3 -march=native -mtune=native -flto`
- SIMD: AVX-512 (if CPU supports) or AVX2
- Libraries: `-luring -llz4 -lboost_fiber -lboost_context -lpthread`

---

### 2. **Runtime Configuration Management** ✅

**Configuration File**: `/etc/meteor/meteor.conf`

**Contents**:
```bash
# Meteor Server Configuration File
# Modify values here and restart: systemctl restart meteor.service

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
METEOR_SNAPSHOT_INTERVAL=1800  # 30 minutes
METEOR_SNAPSHOT_OPS=50000
METEOR_FSYNC_POLICY=2          # everysec

# Health Monitoring
METEOR_HANG_TIMEOUT=30
```

**Systemd Integration** (EnvironmentFile):
```ini
[Service]
EnvironmentFile=/etc/meteor/meteor.conf

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
```

---

### 3. **Configuration Update Script** ✅

**Script**: `/opt/meteor/scripts/meteor-update-config.sh`

**Usage**:
```bash
# Show current configuration
sudo /opt/meteor/scripts/meteor-update-config.sh --show

# Update single parameter
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_MEMORY_MB=32768

# Update multiple parameters
sudo /opt/meteor/scripts/meteor-update-config.sh \
    METEOR_CORES=16 \
    METEOR_SHARDS=16 \
    METEOR_MEMORY_MB=65536

# Change snapshot interval to 1 hour
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_SNAPSHOT_INTERVAL=3600

# Disable persistence
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_PERSISTENCE=0

# Just restart (no config changes)
sudo /opt/meteor/scripts/meteor-update-config.sh --restart
```

**Features**:
- ✅ **Validates configuration keys**
- ✅ **Backs up config before changes** (`/etc/meteor/meteor.conf.backup.TIMESTAMP`)
- ✅ **Automatically restarts services** (meteor + health monitor)
- ✅ **Reloads systemd daemon**
- ✅ **Shows service status after restart**
- ✅ **Safe updates** with validation

---

## 📦 **Complete Usage Workflow**

### **Step 1: Build Package with Custom Binary/Source**

```bash
# Option A: Use existing binary
./create_meteor_package.sh --binary ./my-meteor-server

# Option B: Build from specific source file
./create_meteor_package.sh --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp

# Option C: Auto-detect (will find persistence source automatically)
./create_meteor_package.sh

# With Ubuntu version specification
./create_meteor_package.sh 24 --binary ./my-server
./create_meteor_package.sh 24 --source-file cpp/my-server.cpp
```

---

### **Step 2: Extract & Install**

```bash
# Extract package
tar -xzf meteor-server-*.tar.gz
cd meteor-server-*

# Install with custom configuration
sudo ./install.sh \
    --cores 32 \
    --shards 32 \
    --memory 131072 \
    --snapshot-interval 1800 \
    --fsync-policy 2 \
    --persistence 1

# Result: Creates /etc/meteor/meteor.conf with these values
```

---

### **Step 3: Runtime Configuration Updates** (No Reinstall!)

```bash
# Scenario: Need more memory
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_MEMORY_MB=262144
# ✅ Config updated
# ✅ Service restarted automatically
# ✅ Backup created

# Scenario: Change snapshot frequency (30min → 1 hour)
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_SNAPSHOT_INTERVAL=3600

# Scenario: Scale up cores/shards
sudo /opt/meteor/scripts/meteor-update-config.sh \
    METEOR_CORES=64 \
    METEOR_SHARDS=64

# Scenario: Disable persistence temporarily
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_PERSISTENCE=0

# Scenario: Enable persistence and configure paths
sudo /opt/meteor/scripts/meteor-update-config.sh \
    METEOR_PERSISTENCE=1 \
    METEOR_RDB_PATH=/mnt/ssd/meteor/rdb \
    METEOR_AOF_PATH=/mnt/ssd/meteor/aof
```

---

### **Step 4: Manual Configuration Edit** (Alternative)

```bash
# Edit configuration file directly
sudo vi /etc/meteor/meteor.conf

# Example changes:
# METEOR_MEMORY_MB=262144
# METEOR_SNAPSHOT_INTERVAL=3600

# Restart services to apply
sudo systemctl restart meteor.service
sudo systemctl restart meteor-health-monitor.service
```

---

## 🔧 **All Available Scripts**

| Script | Purpose | Usage |
|--------|---------|-------|
| `meteor-update-config.sh` | **Update config & restart** | `sudo ./meteor-update-config.sh KEY=VALUE` |
| `meteor-health-monitor.sh` | Health monitoring | Auto-started by systemd |
| `meteor-rdb-cleanup.sh` | RDB cleanup (keeps last 3) | Auto-run via cron (hourly) |
| `deploy_meteor.sh` | Initial deployment | Called by install.sh |
| `backup_meteor.sh` | Backup RDB/AOF | Manual backup |

---

## 📊 **Configuration Parameters Reference**

| Parameter | Default | Description | Example |
|-----------|---------|-------------|---------|
| `METEOR_HOST` | `0.0.0.0` | Bind address | `127.0.0.1` |
| `METEOR_PORT` | `6379` | Server port | `6380` |
| `METEOR_CORES` | `8` | CPU cores | `32` |
| `METEOR_SHARDS` | `8` | Shards (match cores) | `32` |
| `METEOR_MEMORY_MB` | `16384` | Max memory (MB) | `131072` |
| `METEOR_PERSISTENCE` | `1` | Enable (1) / Disable (0) | `0` |
| `METEOR_RDB_PATH` | `/var/lib/meteor/snapshots` | RDB directory | `/mnt/ssd/rdb` |
| `METEOR_AOF_PATH` | `/var/lib/meteor/aof` | AOF directory | `/mnt/ssd/aof` |
| `METEOR_SNAPSHOT_INTERVAL` | `1800` | Snapshot interval (seconds) | `3600` |
| `METEOR_SNAPSHOT_OPS` | `50000` | Snapshot after N ops | `100000` |
| `METEOR_FSYNC_POLICY` | `2` | 0=never, 1=always, 2=everysec | `1` |
| `METEOR_HANG_TIMEOUT` | `30` | Hang detection (seconds) | `60` |

---

## 🎯 **Real-World Scenarios**

### **Scenario 1: Production Deployment with Custom Binary**

```bash
# 1. Build custom binary on build server
g++ -std=c++20 -O3 -march=native \
    cpp/meteor_redis_client_compatible_with_persistence.cpp \
    -o meteor-production-v1 \
    -luring -llz4 -lboost_fiber -lboost_context -lpthread

# 2. Create package with custom binary
./create_meteor_package.sh --binary ./meteor-production-v1

# 3. Deploy to production server
scp meteor-server-*.tar.gz prod-server:/tmp/
ssh prod-server
cd /tmp && tar -xzf meteor-server-*.tar.gz
cd meteor-server-*

# 4. Install with production config
sudo ./install.sh \
    --cores 64 \
    --shards 64 \
    --memory 262144 \
    --snapshot-interval 1800 \
    --fsync-policy 2

# 5. Production is running!
systemctl status meteor.service
```

---

### **Scenario 2: Runtime Configuration Tuning**

```bash
# Week 1: Start conservative
sudo ./install.sh --cores 16 --memory 65536

# Week 2: Need more memory (high cache usage)
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_MEMORY_MB=131072
# ✅ Restarted automatically

# Week 3: Increase snapshot frequency for critical data
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_SNAPSHOT_INTERVAL=900
# ✅ Snapshot every 15 minutes now

# Week 4: Scale up to handle more load
sudo /opt/meteor/scripts/meteor-update-config.sh \
    METEOR_CORES=32 \
    METEOR_SHARDS=32 \
    METEOR_MEMORY_MB=262144
# ✅ Server scaled up

# No reinstallation needed for any of these changes!
```

---

### **Scenario 3: Testing Different Sources**

```bash
# Test baseline version
./create_meteor_package.sh \
    --source-file cpp/meteor_baseline_prod_v4.cpp
tar -xzf meteor-server-*.tar.gz && cd meteor-server-* && sudo ./install.sh

# Test persistence version
./create_meteor_package.sh \
    --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp
tar -xzf meteor-server-*.tar.gz && cd meteor-server-* && sudo ./install.sh

# Test custom development version
./create_meteor_package.sh \
    --source-file cpp/my_experimental_features.cpp
tar -xzf meteor-server-*.tar.gz && cd meteor-server-* && sudo ./install.sh
```

---

### **Scenario 4: Multi-Environment Deployment**

```bash
# Development environment
./create_meteor_package.sh --source-file cpp/meteor_dev.cpp
sudo ./install.sh --cores 4 --memory 8192 --persistence 0

# Staging environment
./create_meteor_package.sh --source-file cpp/meteor_staging.cpp
sudo ./install.sh --cores 16 --memory 32768 --snapshot-interval 3600

# Production environment
./create_meteor_package.sh --binary ./meteor-prod-optimized
sudo ./install.sh --cores 64 --memory 262144 --snapshot-interval 1800 --fsync-policy 2
```

---

## 🔍 **Verification & Monitoring**

### **Check Configuration**
```bash
# View current config
sudo /opt/meteor/scripts/meteor-update-config.sh --show

# Check service is using correct config
systemctl show meteor.service | grep EnvironmentFile
# Output: EnvironmentFile=/etc/meteor/meteor.conf

# View actual running parameters (from systemd)
systemctl status meteor.service
```

### **Monitor Changes**
```bash
# Config change history (backups)
ls -lh /etc/meteor/meteor.conf.backup.*

# Service restart history
journalctl -u meteor.service -n 50
```

### **Health Checks**
```bash
# Service status
systemctl status meteor.service
systemctl status meteor-health-monitor.service

# Health monitor logs
tail -f /var/log/meteor/health-monitor.log

# Server logs
journalctl -u meteor.service -f
```

---

## ✅ **Summary of Benefits**

### **1. Flexible Binary Selection**
✅ Use pre-built binaries  
✅ Build from custom source files  
✅ Automatic detection and building  
✅ Full production optimization flags  

### **2. Runtime Configuration**
✅ **No reinstallation needed** for config changes  
✅ All parameters configurable via `/etc/meteor/meteor.conf`  
✅ Automatic service restart after updates  
✅ Configuration backups before changes  
✅ systemd EnvironmentFile integration  

### **3. Production Ready**
✅ Health monitoring with auto-restart  
✅ RDB cleanup (keeps last 3 snapshots)  
✅ Comprehensive logging  
✅ Safe configuration updates with validation  
✅ Complete documentation  

### **4. Ease of Use**
✅ Simple command-line parameters  
✅ `meteor-update-config.sh` for all changes  
✅ No need to understand systemd  
✅ Safe rollback via config backups  

---

## 📝 **Files Created/Modified**

**Modified**:
- `create_meteor_package.sh` (~400 lines added/modified)

**Created in Package**:
- `scripts/meteor-update-config.sh` (configuration update script)
- `scripts/meteor-health-monitor.sh` (health monitoring)
- `scripts/meteor-rdb-cleanup.sh` (RDB cleanup)
- `etc/meteor.conf.template` (configuration template)
- `etc/meteor.conf` (default configuration)
- `systemd/meteor.service` (with EnvironmentFile support)

**Created on Installation**:
- `/etc/meteor/meteor.conf` (runtime configuration)
- `/etc/meteor/meteor.conf.template` (reference template)
- `/etc/systemd/system/meteor.service` (systemd service)
- `/etc/systemd/system/meteor-health-monitor.service` (health monitor)
- `/etc/cron.d/meteor-rdb-cleanup` (RDB cleanup cron)

---

## 🚀 **Next Steps**

1. **Build Package** with your preferred binary/source:
   ```bash
   ./create_meteor_package.sh --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp
   ```

2. **Install** on target server:
   ```bash
   sudo ./install.sh --cores 32 --shards 32 --memory 131072
   ```

3. **Update Configuration** at runtime as needed:
   ```bash
   sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_MEMORY_MB=262144
   ```

4. **Monitor** and adjust:
   ```bash
   sudo /opt/meteor/scripts/meteor-update-config.sh --show
   journalctl -u meteor.service -f
   ```

---

**All requirements complete!** 🎉

✅ Binary path parameter  
✅ Source file parameter  
✅ Configuration via meteor.conf  
✅ Runtime updates with service restart  
✅ No reinstallation needed for config changes  
✅ Production-ready defaults  
✅ Comprehensive documentation  


