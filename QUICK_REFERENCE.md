# Meteor Packaging & Configuration - Quick Reference

## 🚀 Build Package

```bash
# Use specific binary
./create_meteor_package.sh --binary ./my-meteor-server

# Build from specific source
./create_meteor_package.sh --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp

# Auto-detect (uses persistence source if available)
./create_meteor_package.sh
```

---

## 📦 Install

```bash
tar -xzf meteor-server-*.tar.gz && cd meteor-server-*

# Default installation
sudo ./install.sh

# Custom configuration
sudo ./install.sh \
    --cores 32 \
    --shards 32 \
    --memory 131072 \
    --snapshot-interval 1800 \
    --fsync-policy 2 \
    --persistence 1
```

---

## ⚙️ Update Configuration (Runtime)

```bash
# Show current config
sudo /opt/meteor/scripts/meteor-update-config.sh --show

# Update single parameter
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_MEMORY_MB=262144

# Update multiple parameters
sudo /opt/meteor/scripts/meteor-update-config.sh \
    METEOR_CORES=64 \
    METEOR_SHARDS=64 \
    METEOR_MEMORY_MB=262144

# Common updates
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_SNAPSHOT_INTERVAL=3600  # 1 hour
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_PERSISTENCE=0           # Disable
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_FSYNC_POLICY=1          # Always

# Restart without changes
sudo /opt/meteor/scripts/meteor-update-config.sh --restart
```

---

## 📊 Monitoring

```bash
# Service status
systemctl status meteor.service
systemctl status meteor-health-monitor.service
systemctl status meteor-hangdetector.timer

# Server logs
journalctl -u meteor.service -f

# Health monitor logs (continuous)
tail -f /var/log/meteor/health-monitor.log

# Hang detector logs (periodic)
tail -f /var/log/meteor/hang-detector.log

# Combined logs
tail -f /var/log/meteor/health-monitor.log /var/log/meteor/hang-detector.log

# Check configuration
cat /etc/meteor/meteor.conf
```

---

## 🔧 Configuration File

Location: `/etc/meteor/meteor.conf`

```bash
METEOR_PORT=6379
METEOR_CORES=8
METEOR_SHARDS=8
METEOR_MEMORY_MB=16384
METEOR_PERSISTENCE=1
METEOR_SNAPSHOT_INTERVAL=1800  # 30 minutes
METEOR_FSYNC_POLICY=2          # everysec
METEOR_RDB_PATH=/var/lib/meteor/snapshots
METEOR_AOF_PATH=/var/lib/meteor/aof
```

**Edit & Restart**:
```bash
sudo vi /etc/meteor/meteor.conf
sudo systemctl restart meteor.service
```

---

## 📝 Available Scripts

| Script | Command |
|--------|---------|
| **Update Config** | `sudo /opt/meteor/scripts/meteor-update-config.sh KEY=VALUE` |
| **Show Config** | `sudo /opt/meteor/scripts/meteor-update-config.sh --show` |
| **Restart** | `sudo /opt/meteor/scripts/meteor-update-config.sh --restart` |
| **Backup** | `sudo /opt/meteor/scripts/backup_meteor.sh` |

---

## 🎯 Common Scenarios

### Scale Up Resources
```bash
sudo /opt/meteor/scripts/meteor-update-config.sh \
    METEOR_CORES=64 \
    METEOR_SHARDS=64 \
    METEOR_MEMORY_MB=262144
```

### Increase Snapshot Frequency
```bash
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_SNAPSHOT_INTERVAL=900  # 15 min
```

### Disable Persistence (In-Memory Only)
```bash
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_PERSISTENCE=0
```

### Maximum Durability
```bash
sudo /opt/meteor/scripts/meteor-update-config.sh METEOR_FSYNC_POLICY=1  # always
```

---

## 📂 Important Locations

| Path | Description |
|------|-------------|
| `/etc/meteor/meteor.conf` | Configuration file |
| `/opt/meteor/bin/meteor-server` | Server binary |
| `/opt/meteor/scripts/` | Management scripts |
| `/var/lib/meteor/snapshots/` | RDB snapshots |
| `/var/lib/meteor/aof/` | AOF file |
| `/var/log/meteor/` | Log files |

---

## 🆘 Troubleshooting

```bash
# Check service status
systemctl status meteor.service

# View recent logs
journalctl -u meteor.service -n 100

# Test connectivity
redis-cli -h 127.0.0.1 -p 6379 PING

# View configuration backups
ls -lh /etc/meteor/meteor.conf.backup.*

# Restart services
sudo systemctl restart meteor.service
sudo systemctl restart meteor-health-monitor.service
```

---

## 📖 Full Documentation

- **`PACKAGING_CONFIG_MANAGEMENT_GUIDE.md`** - Complete usage guide
- **`PACKAGING_SCRIPT_UPDATE_SUMMARY.md`** - Persistence features
- **`FINAL_PACKAGING_SUMMARY.md`** - Summary of all features

---

**All operations ready for production!** 🎉

