# Meteor Package Testing Instructions - mcache-lssd-sumit VM

## ✅ Testing Requirements

Test the packaging script on `mcache-lssd-sumit` VM to verify:
1. ✅ Correct tar file creation
2. ✅ Installation via tar works correctly
3. ✅ Hang detector and health monitor services configured
4. ✅ **Server restarts if it doesn't respond in 5 seconds after 2 retries**

---

## 🚀 Complete Test Procedure

### **Step 1: Prepare Package on Local Machine**

```bash
cd /Users/sumit.kumar/Documents/personal/repo/meteor

# Create package with persistence source (auto-detects if exists)
./create_meteor_package.sh

# Or specify specific source file
./create_meteor_package.sh --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp

# Package created: meteor-server-8.1-single-cmd-optimized-mget-ubuntu24-YYYYMMDD.tar.gz
```

---

### **Step 2: Transfer Package to VM**

```bash
# Find the package name
PACKAGE=$(ls -t meteor-server-*.tar.gz | head -1)

# Copy to VM
gcloud compute scp "$PACKAGE" mcache-lssd-sumit:/tmp/ \
    --project=<your-gcp-project-id> \
    --zone=<YOUR_ZONE>

# Alternative: Use rsync if direct connection
rsync -avz "$PACKAGE" mcache-lssd-sumit:/tmp/
```

---

### **Step 3: Connect to VM and Install**

```bash
# SSH to VM
gcloud compute ssh mcache-lssd-sumit \
    --project=<your-gcp-project-id> \
    --zone=<YOUR_ZONE>

# On VM
cd /tmp
ls -lh meteor-server-*.tar.gz

# Extract package
tar -xzf meteor-server-*.tar.gz
cd meteor-server-*

# Verify package contents
ls -la
ls -la bin/
ls -la scripts/
ls -la etc/
ls -la systemd/

# Check scripts are executable
ls -la scripts/*.sh

# Verify systemd service file
cat systemd/meteor.service

# Verify config template
cat etc/meteor.conf.template
```

---

### **Step 4: Install Package**

```bash
# Install with default settings (includes health monitor with 5s timeout, 2 retries)
sudo ./install.sh

# Or install with custom settings
sudo ./install.sh \
    --cores 16 \
    --shards 16 \
    --memory 65536 \
    --persistence 1 \
    --snapshot-interval 1800

# Installation will:
# - Create /etc/meteor/meteor.conf
# - Install /etc/systemd/system/meteor.service
# - Install /etc/systemd/system/meteor-health-monitor.service
# - Create /etc/cron.d/meteor-rdb-cleanup
# - Start both services
```

---

### **Step 5: Verify Installation**

#### **5.1 Check Configuration File**
```bash
# View meteor.conf
cat /etc/meteor/meteor.conf

# Should contain:
# METEOR_HEALTH_CHECK_TIMEOUT=5      # 5 seconds
# METEOR_HEALTH_MAX_RETRIES=2        # 2 retries
# METEOR_HEALTH_CHECK_INTERVAL=3     # 3 seconds between checks
```

#### **5.2 Check Services**
```bash
# Check meteor service
systemctl status meteor.service

# Check health monitor service
systemctl status meteor-health-monitor.service

# Both should be active (running)
```

#### **5.3 Check Systemd Service Uses EnvironmentFile**
```bash
# View service file
cat /etc/systemd/system/meteor.service

# Should contain:
# EnvironmentFile=/etc/meteor/meteor.conf
# ExecStart=/opt/meteor/bin/meteor-server -h ${METEOR_HOST} -p ${METEOR_PORT} ...
```

#### **5.4 Check Health Monitor Logs**
```bash
# View health monitor logs
tail -f /var/log/meteor/health-monitor.log

# Should show:
# 🏥 Meteor Health Monitor started
# Config: timeout=5s, max_retries=2, check_interval=3s
```

---

### **Step 6: Test Direct Config Edit & Reload**

#### **6.1 Edit Config Directly**
```bash
# Backup current config
sudo cp /etc/meteor/meteor.conf /etc/meteor/meteor.conf.backup

# Edit config directly (change memory or other settings)
sudo vi /etc/meteor/meteor.conf

# Example changes:
# METEOR_MEMORY_MB=131072
# METEOR_SNAPSHOT_INTERVAL=3600
```

#### **6.2 Reload & Restart**
```bash
# Reload systemd daemon to pick up new config
sudo systemctl daemon-reload

# Restart meteor service
sudo systemctl restart meteor.service

# Restart health monitor (if health settings changed)
sudo systemctl restart meteor-health-monitor.service

# Verify new config is active
ps aux | grep meteor-server
# Check command line args match new config
```

#### **6.3 Verify Service Picked Up New Config**
```bash
# Check service environment
sudo systemctl show meteor.service | grep EnvironmentFile
# Output: EnvironmentFile=/etc/meteor/meteor.conf

# Check actual command being run
sudo systemctl status meteor.service
# Should show ExecStart with new values
```

---

### **Step 7: Test Health Monitor & Hang Detection**

#### **7.1 Test Normal Operation**
```bash
# Check server is responding
redis-cli -h 127.0.0.1 -p 6379 PING
# Should return: PONG

# Check health monitor logs
tail -20 /var/log/meteor/health-monitor.log
# Should show successful health checks
```

#### **7.2 Simulate Server Hang (Kill Server Process)**
```bash
# Find meteor server process
ps aux | grep meteor-server

# Kill the process (simulate hang)
sudo pkill -9 -f meteor-server

# Watch health monitor logs in real-time
tail -f /var/log/meteor/health-monitor.log

# Expected behavior:
# ⚠️  Health check failed (1/2) - timeout after 5s
# (wait 3 seconds)
# ⚠️  Health check failed (2/2) - timeout after 5s
# 💥 Server not responding after 2 retries, triggering restart via systemd
# ⏳ Waiting 10 seconds for server to stabilize...
# ✅ Server recovered after 2 failure(s)
```

#### **7.3 Verify Auto-Restart**
```bash
# Check server was restarted
systemctl status meteor.service
# Should show: Active: active (running)

# Check restart count
systemctl show meteor.service | grep NRestarts
# Should show at least 1 restart

# Verify server is responding
redis-cli -h 127.0.0.1 -p 6379 PING
# Should return: PONG
```

#### **7.4 Test Timing (5 seconds, 2 retries)**
```bash
# Time the hang detection process
# Kill server
sudo pkill -9 -f meteor-server

# Start timer and watch logs
date && tail -f /var/log/meteor/health-monitor.log

# Expected timeline:
# T+0s:  Health check #1 fails (5s timeout)
# T+5s:  Wait 3 seconds
# T+8s:  Health check #2 fails (5s timeout)
# T+13s: Trigger restart
# T+23s: Server should be back online

# Total time: ~13-15 seconds (5s + 3s + 5s)
```

---

### **Step 8: Test Config Update Script**

#### **8.1 Use Update Script**
```bash
# Show current configuration
sudo /opt/meteor/scripts/meteor-update-config.sh --show

# Update memory
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_MEMORY_MB=262144

# Expected output:
# [CONFIG] Updating configuration...
#   METEOR_MEMORY_MB = 262144
# [CONFIG] Configuration updated successfully
# [CONFIG] Restarting Meteor service to apply changes...
# [CONFIG] Service restarted successfully

# Verify config changed
cat /etc/meteor/meteor.conf | grep METEOR_MEMORY_MB
# Should show: METEOR_MEMORY_MB=262144

# Verify service restarted with new config
ps aux | grep meteor-server
# Check command line has -m 262144
```

#### **8.2 Update Multiple Parameters**
```bash
sudo /opt/meteor/scripts/meteor-update-config.sh \
    METEOR_CORES=32 \
    METEOR_SHARDS=32 \
    METEOR_MEMORY_MB=131072

# Verify all changed
cat /etc/meteor/meteor.conf
```

---

### **Step 9: Test RDB Cleanup**

```bash
# Check RDB cleanup cron job
cat /etc/cron.d/meteor-rdb-cleanup

# Should show:
# 0 * * * * root /opt/meteor/scripts/meteor-rdb-cleanup.sh

# Test manually
sudo /opt/meteor/scripts/meteor-rdb-cleanup.sh

# Check cleanup logs
cat /var/log/meteor/rdb-cleanup.log
```

---

### **Step 10: Load Test & Stability**

```bash
# Write test data
for i in {1..1000}; do
    redis-cli -h 127.0.0.1 -p 6379 SET test_key_$i test_value_$i > /dev/null
done

# Verify data
redis-cli -h 127.0.0.1 -p 6379 GET test_key_500

# Run load test (if memtier_benchmark available)
memtier_benchmark -s 127.0.0.1 -p 6379 \
    --protocol=redis \
    --clients=50 \
    --threads=10 \
    --requests=10000 \
    --data-size=1024 \
    --pipeline=10

# Monitor health during load
tail -f /var/log/meteor/health-monitor.log

# Server should remain stable
```

---

## ✅ Verification Checklist

Use this checklist to verify all requirements:

- [ ] **Package Creation**
  - [ ] Tar file created successfully
  - [ ] Package contains all required files (bin, scripts, etc, systemd)
  - [ ] Scripts are executable

- [ ] **Installation**
  - [ ] Package extracts correctly
  - [ ] Installation completes without errors
  - [ ] meteor.service created and active
  - [ ] meteor-health-monitor.service created and active
  - [ ] RDB cleanup cron job installed

- [ ] **Configuration File**
  - [ ] /etc/meteor/meteor.conf exists
  - [ ] Contains health monitor settings (5s timeout, 2 retries)
  - [ ] Systemd service uses EnvironmentFile

- [ ] **Direct Config Edit**
  - [ ] Can edit /etc/meteor/meteor.conf manually
  - [ ] systemctl restart picks up new config
  - [ ] Service runs with updated parameters

- [ ] **Config Update Script**
  - [ ] meteor-update-config.sh exists and is executable
  - [ ] Can update single parameter
  - [ ] Can update multiple parameters
  - [ ] Automatically restarts service
  - [ ] Creates backup before changes

- [ ] **Health Monitor**
  - [ ] Health monitor service is running
  - [ ] Logs show config (timeout=5s, max_retries=2, interval=3s)
  - [ ] Successfully detects healthy server

- [ ] **Hang Detection (5s, 2 retries)**
  - [ ] Detects server hang/kill
  - [ ] First retry after ~5 seconds
  - [ ] Second retry after ~8 seconds (5s + 3s)
  - [ ] Triggers restart after 2 failed retries (~13 seconds total)
  - [ ] Server restarts automatically via systemd
  - [ ] Server recovers and responds normally
  - [ ] Health monitor logs show full cycle

- [ ] **RDB Cleanup**
  - [ ] Cron job installed
  - [ ] Script executes successfully
  - [ ] Keeps last 3 snapshots

---

## 📊 Expected Test Results

### **Timing Test Results**

| Event | Expected Time | Description |
|-------|---------------|-------------|
| Health Check #1 | T+0s to T+5s | First PING timeout (5s) |
| Wait | T+5s to T+8s | Check interval (3s) |
| Health Check #2 | T+8s to T+13s | Second PING timeout (5s) |
| Restart Trigger | T+13s | After 2 retries |
| Server Stable | T+23s | 10s stabilization wait |
| Recovery | T+23s+ | Server responding |

### **Health Monitor Log Example**

```
[2025-10-17 10:00:00] 🏥 Meteor Health Monitor started
[2025-10-17 10:00:00]    Config: timeout=5s, max_retries=2, check_interval=3s
[2025-10-17 10:00:03] ⚠️  Health check failed (1/2) - timeout after 5s
[2025-10-17 10:00:11] ⚠️  Health check failed (2/2) - timeout after 5s
[2025-10-17 10:00:11] 💥 Server not responding after 2 retries, triggering restart via systemd
[2025-10-17 10:00:11] ⏳ Waiting 10 seconds for server to stabilize...
[2025-10-17 10:00:24] ✅ Server recovered after 2 failure(s)
```

---

## 🐛 Troubleshooting

### **Issue: Health monitor not detecting hangs**
```bash
# Check health monitor is running
systemctl status meteor-health-monitor.service

# Check health monitor can reach server
redis-cli -h 127.0.0.1 -p 6379 PING

# Check health monitor config
tail /var/log/meteor/health-monitor.log
```

### **Issue: Config changes not taking effect**
```bash
# Ensure systemd daemon is reloaded
sudo systemctl daemon-reload

# Restart service
sudo systemctl restart meteor.service

# Check service is using EnvironmentFile
sudo systemctl show meteor.service | grep EnvironmentFile
```

### **Issue: Service won't start**
```bash
# Check service logs
journalctl -u meteor.service -n 50

# Check config file syntax
cat /etc/meteor/meteor.conf

# Check binary exists and is executable
ls -la /opt/meteor/bin/meteor-server
```

---

## 📝 Report Template

After testing, create a report with these sections:

```
# Meteor Packaging Test Report

## VM Details
- VM Name: mcache-lssd-sumit
- Date: YYYY-MM-DD
- Tester: [Your Name]

## Test Results

### 1. Package Creation: ✅ / ❌
- Package file: [filename]
- Size: [size]
- Notes: [any issues]

### 2. Installation: ✅ / ❌
- Installation method: tar extract + ./install.sh
- Services started: ✅ / ❌
- Config created: ✅ / ❌
- Notes: [any issues]

### 3. Direct Config Edit: ✅ / ❌
- Config file editable: ✅ / ❌
- Service reload works: ✅ / ❌
- New config active: ✅ / ❌
- Notes: [any issues]

### 4. Health Monitor (5s, 2 retries): ✅ / ❌
- Service running: ✅ / ❌
- Config correct (5s, 2 retries): ✅ / ❌
- Hang detection time: [actual time]
- Auto-restart works: ✅ / ❌
- Notes: [any issues]

### 5. Overall: ✅ / ❌
[Summary of test results]
```

---

**All test procedures documented!** 🎉

Run these tests on the VM to verify the packaging script works correctly.


