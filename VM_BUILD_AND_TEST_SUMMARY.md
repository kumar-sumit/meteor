# VM Build and Test Summary

## ✅ Complete Solution: Build and Install on VM

### 🎯 Architecture

**Correct Separation**:
1. **`create_meteor_package.sh`**: Creates tar.gz with scripts and binaries (NO installation)
2. **`install.sh`** (in package): Deploys on VM and configures systemd services

---

## ⏱️ **Updated Timings**

### Health Monitor (Continuous)
- **Check Interval**: Every **3 seconds**
- **Timeout**: **2 seconds** per PING
- **Max Retries**: **2 failures**
- **Detection Time**: ~10 seconds (2s + 3s + 2s + 3s)
- **Purpose**: Fast detection, continuous monitoring

### Hang Detector (Periodic Timer)
- **Check Interval**: Every **5 seconds** (via systemd timer)
- **Timeout**: **2 seconds** per PING
- **Max Failures**: **2 failures**
- **Detection Time**: ~12 seconds (5s wait + 2s + 5s wait + 2s)
- **Purpose**: Backup detection, independent of health monitor

---

## 📦 Configuration in `/etc/meteor/meteor.conf`

```bash
# Health Monitoring Configuration
METEOR_HEALTH_CHECK_TIMEOUT=2      # 2 seconds timeout
METEOR_HEALTH_MAX_RETRIES=2        # 2 retries before restart
METEOR_HEALTH_CHECK_INTERVAL=3     # Check every 3 seconds

# Hang Detector Configuration (periodic check every 5 seconds via timer)
METEOR_HANG_TIMEOUT=2              # 2 seconds timeout
METEOR_HANG_MAX_FAILURES=2         # 2 failures before restart
```

---

## 🚀 **Usage: Build and Test on VM**

### Method 1: Automated Script

```bash
# Run the automated build and test script
./build_and_test_on_vm.sh
```

**What it does**:
1. ✅ Transfers source files to VM (`/tmp/meteor-build/`)
2. ✅ Builds package on VM using `create_meteor_package.sh`
3. ✅ Installs package using `install.sh`
4. ✅ Verifies installation (services, logs, connectivity)

---

### Method 2: Manual Steps

#### Step 1: Transfer Files
```bash
PROJECT="<your-gcp-project-id>"
ZONE="asia-southeast1-a"
VM="mcache-lssd-sumit"

# Transfer source files
gcloud compute scp --recurse \
    cpp/meteor_redis_client_compatible_with_persistence.cpp \
    cpp/meteor_persistence_module.hpp \
    create_meteor_package.sh \
    deployment/ \
    "$VM:/tmp/meteor-build/" \
    --project="$PROJECT" \
    --zone="$ZONE"
```

#### Step 2: SSH to VM and Build
```bash
# SSH to VM
gcloud compute ssh "$VM" --project="$PROJECT" --zone="$ZONE"

# On VM
cd /tmp/meteor-build
chmod +x create_meteor_package.sh

# Build package
./create_meteor_package.sh --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp

# Extract package
tar -xzf meteor-server-*.tar.gz
cd meteor-server-*/
```

#### Step 3: Install
```bash
# Install with persistence enabled
sudo ./install.sh \
    --cores 4 \
    --shards 4 \
    --memory 16384 \
    --persistence 1 \
    --snapshot-interval 1800
```

---

## 🔍 **Verification Checklist**

After installation, verify:

### 1. Services Running
```bash
systemctl status meteor.service
systemctl status meteor-health-monitor.service
systemctl status meteor-hangdetector.timer
```

**Expected**: All active/running

### 2. Configuration File
```bash
cat /etc/meteor/meteor.conf | grep -E 'HEALTH|HANG'
```

**Expected**:
```
METEOR_HEALTH_CHECK_TIMEOUT=2
METEOR_HEALTH_MAX_RETRIES=2
METEOR_HEALTH_CHECK_INTERVAL=3
METEOR_HANG_TIMEOUT=2
METEOR_HANG_MAX_FAILURES=2
```

### 3. Scripts Exist
```bash
ls -la /opt/meteor/scripts/meteor-health-monitor.sh
ls -la /opt/meteor/scripts/meteor-hangdetector.sh
```

**Expected**: Both executable

### 4. Systemd Services
```bash
ls -la /etc/systemd/system/meteor-health-monitor.service
ls -la /etc/systemd/system/meteor-hangdetector.service
ls -la /etc/systemd/system/meteor-hangdetector.timer
```

**Expected**: All three exist

### 5. Logs Active
```bash
sudo tail -f /var/log/meteor/health-monitor.log
sudo tail -f /var/log/meteor/hang-detector.log
```

**Expected**: Both logs updating

### 6. Redis Connectivity
```bash
redis-cli -h 127.0.0.1 -p 6379 PING
redis-cli -h 127.0.0.1 -p 6379 SET test_key test_value
redis-cli -h 127.0.0.1 -p 6379 GET test_key
```

**Expected**: PONG, OK, test_value

---

## 🧪 **Testing Hang Detection**

### Test 1: Simulate Server Hang
```bash
# On VM
sudo pkill -9 -f meteor-server

# Watch health monitor (should detect in ~10 seconds)
sudo tail -f /var/log/meteor/health-monitor.log

# Expected output:
# [timestamp] HEALTHMON: ⚠️  Health check failed (1/2) - timeout after 2s
# [timestamp] HEALTHMON: ⚠️  Health check failed (2/2) - timeout after 2s
# [timestamp] HEALTHMON: 💥 Server not responding after 2 retries, triggering restart
```

### Test 2: Verify Hang Detector (Backup)
```bash
# Watch hang detector
sudo tail -f /var/log/meteor/hang-detector.log

# Expected output:
# [timestamp] HANG-DETECTOR: ⚠️  Server not responding (failure 1/2) - timeout: 2s
# [timestamp] HANG-DETECTOR: ⚠️  Server not responding (failure 2/2) - timeout: 2s
# [timestamp] HANG-DETECTOR: 💥 HANG DETECTED after 2 failures, triggering restart
```

### Test 3: Verify Auto-Recovery
```bash
# After restart, verify server is responding
redis-cli -h 127.0.0.1 -p 6379 PING

# Verify data persisted (if you wrote data before)
redis-cli -h 127.0.0.1 -p 6379 GET test_key
```

---

## 📊 **Expected Timeline**

### Scenario: Server Hang

| Time | Health Monitor | Hang Detector |
|------|----------------|---------------|
| T+0s | Server hangs | Server hangs |
| T+2s | Check #1 fails (2s timeout) | - |
| T+5s | Wait 3s | - |
| T+7s | Check #2 fails (2s timeout) | Check #1 fails (2s timeout) |
| T+10s | **Triggers restart** ✅ | Wait 5s |
| T+12s | - | Check #2 (but server already restarted) |

**Result**: Health monitor detects and restarts in ~10 seconds.  
**Backup**: If health monitor fails, hang detector catches it within ~12 seconds.

---

## 🛡️ **Redundant Protection**

### Why Both Services?

1. **Health Monitor** (Fast):
   - Always running in background
   - Checks every 3 seconds
   - 2-second timeout
   - Detects issues in ~10 seconds
   - Primary protection

2. **Hang Detector** (Backup):
   - Runs via systemd timer (more reliable)
   - Checks every 5 seconds
   - Independent state tracking
   - Detects issues in ~12 seconds
   - Secondary protection

3. **Together**:
   - If health monitor crashes → hang detector still works
   - If timer skips a run → health monitor catches it
   - **Maximum uptime guarantee**

---

## 🔧 **Customization**

### Make Health Monitor Faster
```bash
# Edit config
sudo vi /etc/meteor/meteor.conf

# Change to check every second
METEOR_HEALTH_CHECK_INTERVAL=1
METEOR_HEALTH_CHECK_TIMEOUT=1
METEOR_HEALTH_MAX_RETRIES=2

# Restart service
sudo systemctl restart meteor-health-monitor.service
```

### Make Hang Detector More Aggressive
```bash
# Edit timer to run every 3 seconds
sudo vi /etc/systemd/system/meteor-hangdetector.timer

# Change OnUnitActiveSec=5 to OnUnitActiveSec=3

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart meteor-hangdetector.timer
```

---

## ✅ **Success Criteria**

Installation is successful when:

- ✅ `meteor.service` active and running
- ✅ `meteor-health-monitor.service` active and running
- ✅ `meteor-hangdetector.timer` active
- ✅ Redis PING returns PONG
- ✅ Both log files updating
- ✅ Simulated hang triggers auto-restart within 10-12 seconds
- ✅ Server recovers and loads data from RDB/AOF

---

## 📝 **Files Created on VM**

### Package Build
- `/tmp/meteor-build/` - Source files and build artifacts
- `/tmp/meteor-build/meteor-server-*.tar.gz` - Built package

### Installation
- `/opt/meteor/bin/meteor-server` - Server binary
- `/opt/meteor/scripts/meteor-health-monitor.sh` - Health monitor script
- `/opt/meteor/scripts/meteor-hangdetector.sh` - Hang detector script
- `/opt/meteor/scripts/meteor-update-config.sh` - Config update script
- `/opt/meteor/scripts/meteor-rdb-cleanup.sh` - RDB cleanup script

### Configuration
- `/etc/meteor/meteor.conf` - Main configuration
- `/etc/meteor/meteor.conf.template` - Template for reference

### Systemd
- `/etc/systemd/system/meteor.service` - Main service
- `/etc/systemd/system/meteor-health-monitor.service` - Health monitor service
- `/etc/systemd/system/meteor-hangdetector.service` - Hang detector service
- `/etc/systemd/system/meteor-hangdetector.timer` - Hang detector timer

### Data & Logs
- `/var/lib/meteor/snapshots/` - RDB snapshots
- `/var/lib/meteor/aof/` - AOF file
- `/var/log/meteor/health-monitor.log` - Health monitor logs
- `/var/log/meteor/hang-detector.log` - Hang detector logs

---

## 🎯 **Ready to Run**

```bash
# Execute the automated build and test
./build_and_test_on_vm.sh
```

This will:
1. Transfer source files to VM
2. Build package on VM
3. Install package
4. Verify all services
5. Test Redis connectivity

**All done in one command!** 🚀


