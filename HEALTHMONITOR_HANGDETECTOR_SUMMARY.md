# ✅ Both Health Monitor and Hang Detector Services Implemented

## 🎯 Complete Implementation

The `create_meteor_package.sh` script now includes **BOTH** monitoring services for comprehensive server protection:

---

## 📊 Services Overview

| Service | Type | Frequency | Purpose |
|---------|------|-----------|---------|
| **meteor-health-monitor** | Continuous Daemon | Every 3s | Continuous health monitoring |
| **meteor-hangdetector** | Periodic Timer | Every 10s | Hang detection with auto-restart |

---

## 🔄 Service 1: Health Monitor (Continuous)

**Service**: `meteor-health-monitor.service`  
**Type**: Continuous daemon (always running)  
**Script**: `/opt/meteor/scripts/meteor-health-monitor.sh`

### Configuration
```bash
METEOR_HEALTH_CHECK_TIMEOUT=5      # Seconds to wait for PING
METEOR_HEALTH_MAX_RETRIES=2        # Retries before restart
METEOR_HEALTH_CHECK_INTERVAL=3     # Seconds between checks
```

### Behavior
- Runs continuously in a loop
- Checks server health every 3 seconds
- On failure: waits and retries
- After 2 failures: restarts meteor.service
- Logs to `/var/log/meteor/health-monitor.log`

### Log Format
```
[2025-10-17 10:00:00] HEALTHMON: 🏥 Meteor Health Monitor started
[2025-10-17 10:00:00] HEALTHMON:    Config: timeout=5s, max_retries=2, check_interval=3s
[2025-10-17 10:00:03] HEALTHMON: ⚠️  Health check failed (1/2) - timeout after 5s
[2025-10-17 10:00:11] HEALTHMON: ⚠️  Health check failed (2/2) - timeout after 5s
[2025-10-17 10:00:11] HEALTHMON: 💥 Server not responding after 2 retries, triggering restart
```

---

## 🚨 Service 2: Hang Detector (Periodic)

**Service**: `meteor-hangdetector.service`  
**Timer**: `meteor-hangdetector.timer`  
**Type**: Periodic check via systemd timer  
**Script**: `/opt/meteor/scripts/meteor-hangdetector.sh`

### Configuration
```bash
METEOR_HANG_TIMEOUT=5              # Seconds to wait for PING
METEOR_HANG_MAX_FAILURES=2         # Failures before restart
```

### Timer Configuration
- Runs every **10 seconds**
- Starts 30 seconds after boot
- Accuracy: 2 seconds

### Behavior
- Runs periodically via systemd timer
- Checks if server responds within 5 seconds
- Tracks failures across runs using `/tmp/meteor-hang-failure-count`
- After 2 consecutive failures: restarts meteor.service
- Resets counter on successful check
- Logs to `/var/log/meteor/hang-detector.log`

### Log Format
```
[2025-10-17 10:00:00] HANG-DETECTOR: ⚠️  Server not responding (failure 1/2) - timeout: 5s
[2025-10-17 10:00:10] HANG-DETECTOR: ⚠️  Server not responding (failure 2/2) - timeout: 5s
[2025-10-17 10:00:10] HANG-DETECTOR: 💥 HANG DETECTED after 2 failures, triggering restart
[2025-10-17 10:00:10] HANG-DETECTOR: 🔄 Initiating systemd restart...
[2025-10-17 10:00:10] HANG-DETECTOR: ✅ Restart initiated, failure count reset
```

---

## 🔧 Configuration Files

### `/etc/meteor/meteor.conf`
```bash
# Health Monitoring Configuration
METEOR_HEALTH_CHECK_TIMEOUT=5      # Seconds to wait for PING response (default: 5)
METEOR_HEALTH_MAX_RETRIES=2        # Number of retries before restart (default: 2)
METEOR_HEALTH_CHECK_INTERVAL=3     # Seconds between health checks (default: 3)

# Hang Detector Configuration (periodic check via timer)
METEOR_HANG_TIMEOUT=5              # Seconds to wait for PING response (default: 5)
METEOR_HANG_MAX_FAILURES=2         # Number of failures before restart (default: 2)
```

### Editing Configuration
```bash
# Edit directly
sudo vi /etc/meteor/meteor.conf

# Restart services to apply changes
sudo systemctl restart meteor-health-monitor.service
sudo systemctl restart meteor-hangdetector.service
```

---

## 📦 Package Contents

### Scripts Created
```
scripts/
├── meteor-health-monitor.sh    # Continuous health monitoring
├── meteor-hangdetector.sh      # Periodic hang detection
├── meteor-update-config.sh     # Config updates
└── meteor-rdb-cleanup.sh       # RDB cleanup
```

### Systemd Services Created
```
/etc/systemd/system/
├── meteor.service                      # Main meteor server
├── meteor-health-monitor.service       # Health monitor daemon
├── meteor-hangdetector.service         # Hang detector service
└── meteor-hangdetector.timer           # Hang detector timer
```

---

## 🚀 Installation

```bash
# Install with defaults (both services enabled)
sudo ./install.sh

# Both services are enabled by default
```

---

## 🔍 Verification

### Check All Services
```bash
# Main server
systemctl status meteor.service

# Health monitor (continuous)
systemctl status meteor-health-monitor.service

# Hang detector timer (periodic)
systemctl status meteor-hangdetector.timer

# Check if timer is active
systemctl list-timers | grep meteor
```

### Check Logs
```bash
# Health monitor logs (continuous)
tail -f /var/log/meteor/health-monitor.log

# Hang detector logs (periodic)
tail -f /var/log/meteor/hang-detector.log

# Combined systemd logs
journalctl -u meteor.service -u meteor-health-monitor.service -u meteor-hangdetector.service -f
```

---

## 🧪 Testing

### Test Health Monitor (Continuous Service)
```bash
# Kill meteor server
sudo pkill -9 -f meteor-server

# Watch health monitor logs
tail -f /var/log/meteor/health-monitor.log

# Expected: Detects failure within ~13 seconds (5s + 3s + 5s)
# Expected: Triggers restart automatically
```

### Test Hang Detector (Periodic Timer)
```bash
# Kill meteor server
sudo pkill -9 -f meteor-server

# Watch hang detector logs
tail -f /var/log/meteor/hang-detector.log

# Expected: Detects failure within ~20 seconds (10s check interval × 2)
# Expected: Triggers restart automatically
```

---

## 🛡️ Redundant Protection

### Why Both Services?

**Health Monitor (Continuous)**:
- ✅ Fast detection (~13 seconds max)
- ✅ Always running, immediate response
- ✅ Best for transient failures
- ❌ Single point of failure if it crashes

**Hang Detector (Periodic)**:
- ✅ Independent of health monitor
- ✅ Systemd timer ensures it runs even if something fails
- ✅ Tracks state across runs
- ✅ Backup if health monitor fails
- ❌ Slower detection (~20 seconds max)

**Together**:
- 🛡️ **Redundant protection**
- 🛡️ If health monitor crashes, hang detector still works
- 🛡️ If hang detector misses a run, health monitor catches it
- 🛡️ **Maximum uptime guarantee**

---

## 📊 Detection Timing

### Health Monitor Timeline
```
T+0s:  Health check #1 fails (5s timeout)
T+5s:  Wait 3s
T+8s:  Health check #2 fails (5s timeout)
T+13s: Trigger restart
Total: ~13 seconds
```

### Hang Detector Timeline
```
T+0s:  Server hangs
T+10s: Hang detector check #1 fails (5s timeout)
T+20s: Hang detector check #2 fails (5s timeout)
T+20s: Trigger restart
Total: ~20 seconds
```

### Combined Coverage
- **Fastest**: 13 seconds (health monitor)
- **Backup**: 20 seconds (hang detector)
- **Redundancy**: Both check independently

---

## 🔧 Customization

### Adjust Timings
```bash
# Edit config
sudo vi /etc/meteor/meteor.conf

# Make health monitor faster
METEOR_HEALTH_CHECK_INTERVAL=2     # Check every 2 seconds
METEOR_HEALTH_MAX_RETRIES=2        # Still 2 retries

# Make hang detector more aggressive
METEOR_HANG_TIMEOUT=3              # 3 second timeout
METEOR_HANG_MAX_FAILURES=1         # Only 1 failure needed

# Restart services
sudo systemctl restart meteor-health-monitor.service
sudo systemctl restart meteor-hangdetector.service
```

### Modify Timer Frequency
```bash
# Edit timer
sudo vi /etc/systemd/system/meteor-hangdetector.timer

# Change OnUnitActiveSec=10 to your desired interval
OnUnitActiveSec=5   # Check every 5 seconds instead of 10

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart meteor-hangdetector.timer
```

---

## 📝 Uninstall

```bash
# Uninstall removes ALL services
sudo ./install.sh --uninstall

# Removes:
# - meteor.service
# - meteor-health-monitor.service
# - meteor-hangdetector.service
# - meteor-hangdetector.timer
```

---

## ✅ Verification Checklist

- [ ] **meteor.service** active and running
- [ ] **meteor-health-monitor.service** active and running
- [ ] **meteor-hangdetector.timer** active
- [ ] Both logs updating (`/var/log/meteor/health-monitor.log`, `/var/log/meteor/hang-detector.log`)
- [ ] Can edit `/etc/meteor/meteor.conf` directly
- [ ] `systemctl restart` applies new config
- [ ] Simulated hang triggers auto-restart
- [ ] Both services restart server independently

---

## 🎉 Summary

✅ **Both services implemented**:
- `meteor-health-monitor.service` - Continuous monitoring
- `meteor-hangdetector.timer` + `meteor-hangdetector.service` - Periodic checks

✅ **Configuration managed via** `/etc/meteor/meteor.conf`

✅ **Redundant protection**:
- Fast detection (13s) via health monitor
- Backup detection (20s) via hang detector
- Independent operation for maximum reliability

✅ **Production ready**:
- Both services auto-start on boot
- Both services restart server independently
- Comprehensive logging
- Easy customization

---

**All requirements met!** 🎉

Both hangdetector and healthmonitor services are now fully implemented and integrated.


