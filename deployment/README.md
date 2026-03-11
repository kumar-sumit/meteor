# Meteor Server - Enterprise Production Deployment

This directory contains enterprise-level production deployment tools for the Meteor high-performance Redis-compatible server.

## 🚀 Quick Deployment

### Prerequisites
- Linux server (Ubuntu 18.04+, CentOS 7+, RHEL 7+)
- Root access or sudo privileges
- Meteor server binary (`meteor_race_fix`)

### One-Command Deployment
```bash
sudo ./scripts/deploy_meteor.sh
```

## 📁 Directory Structure

```
deployment/
├── scripts/
│   ├── deploy_meteor.sh      # Main deployment script
│   └── backup_meteor.sh      # Backup and recovery script
├── config/
│   └── production.conf       # Production configuration template
├── systemd/
│   └── meteor.service        # Systemd service definition
├── monitoring/
│   ├── telegraf_meteor.conf  # Telegraf monitoring config
│   └── grafana_dashboard.json # Grafana dashboard
└── README.md                 # This file
```

## 🔧 Deployment Features

### Enterprise-Grade Features
- ✅ **Systemd Integration**: Full systemd service with auto-restart
- ✅ **Security Hardening**: Restricted permissions, isolated processes
- ✅ **Resource Management**: CPU/Memory limits and optimization
- ✅ **Monitoring Ready**: Telegraf/Grafana integration
- ✅ **Log Management**: Structured logging with rotation
- ✅ **Health Checks**: Automated health monitoring
- ✅ **Backup System**: Automated backup and retention
- ✅ **System Optimization**: Kernel tuning for performance

### Deployment Components
1. **System Dependencies**: Automatic installation of required packages
2. **User Management**: Dedicated `meteor` system user
3. **Directory Structure**: Standard FHS-compliant paths
4. **Configuration**: Production-tuned configuration
5. **Service Management**: Systemd service with watchdog
6. **Monitoring**: Metrics collection and health checks
7. **Security**: Sandboxing and access controls
8. **Optimization**: System-level performance tuning

## 📊 Monitoring Stack

### Telegraf Configuration
The deployment includes Telegraf configuration that monitors:
- Server performance metrics (ops/sec, latency)
- Cache statistics (hit/miss rates)
- System resources (CPU, memory, disk, network)
- Process health and connectivity
- Custom application metrics

### Grafana Dashboard
Ready-to-import Grafana dashboard provides:
- Real-time performance visualization
- Cache efficiency metrics
- Resource utilization trends
- Alert-ready metric thresholds
- Historical analysis capabilities

## 🔐 Security Features

### Process Isolation
- Dedicated system user (`meteor`)
- Restricted filesystem access
- Network namespace isolation
- Capability dropping
- No new privilege escalation

### System Hardening
- Memory execution prevention
- Kernel module protection
- Control group protection
- Real-time restrictions
- System call filtering

## 📈 Production Configuration

### Key Settings
```bash
# Performance
cores = 8
memory = 16384
pipeline-enabled = true
work-stealing = true
numa-aware = true

# Persistence
save-snapshots = true
snapshot-interval = 300

# Monitoring
metrics-enabled = true
health-check-enabled = true

# Security
protected-mode = true
max-clients = 10000
```

### File Locations
- **Binary**: `/opt/meteor/bin/meteor-server`
- **Config**: `/etc/meteor/meteor.conf`
- **Data**: `/var/lib/meteor/`
- **Logs**: `/var/log/meteor/`
- **Service**: `/etc/systemd/system/meteor.service`

## 🛠️ Service Management

### Basic Operations
```bash
# Start service
sudo systemctl start meteor

# Stop service
sudo systemctl stop meteor

# Restart service
sudo systemctl restart meteor

# Check status
sudo systemctl status meteor

# View logs
sudo journalctl -u meteor -f
```

### Configuration Reload
```bash
# Reload configuration without restart
sudo systemctl reload meteor
```

### Health Check
```bash
# Manual health check
/opt/meteor/bin/healthcheck.sh

# Test connectivity
redis-cli -h 127.0.0.1 -p 6379 ping
```

## 🔄 Backup and Recovery

### Automated Backups
```bash
# Run backup manually
sudo /opt/meteor/bin/backup_meteor.sh

# Setup automatic backups (daily at 2 AM)
echo "0 2 * * * root /opt/meteor/bin/backup_meteor.sh" >> /etc/crontab
```

### Recovery Process
```bash
# Stop service
sudo systemctl stop meteor

# Restore from backup
sudo tar -xzf /backup/meteor/meteor_backup_YYYYMMDD_HHMMSS.tar.gz -C /var/lib/meteor/

# Fix ownership
sudo chown -R meteor:meteor /var/lib/meteor/

# Start service
sudo systemctl start meteor
```

## 📊 Metrics and Alerting

### Available Metrics
- `meteor_commands_total` - Total commands processed
- `meteor_cache_hits_total` - Cache hit count
- `meteor_cache_misses_total` - Cache miss count
- `meteor_connected_clients` - Active client connections
- `meteor_memory_usage_bytes` - Memory consumption
- `meteor_operations_per_second` - Current throughput

### Setting Up Telegraf
```bash
# Install Telegraf
sudo apt install telegraf  # Ubuntu/Debian
sudo yum install telegraf  # CentOS/RHEL

# Copy configuration
sudo cp monitoring/telegraf_meteor.conf /etc/telegraf/telegraf.d/

# Restart Telegraf
sudo systemctl restart telegraf
```

### Setting Up Grafana
```bash
# Import dashboard
# 1. Open Grafana UI
# 2. Go to "+" -> Import
# 3. Upload monitoring/grafana_dashboard.json
```

## 🔍 Troubleshooting

### Common Issues

**Service won't start**
```bash
# Check system logs
sudo journalctl -u meteor --no-pager

# Verify configuration
sudo -u meteor /opt/meteor/bin/meteor-server --config /etc/meteor/meteor.conf --test-config

# Check permissions
sudo ls -la /var/lib/meteor/ /var/log/meteor/
```

**High CPU/Memory usage**
```bash
# Check configuration
grep -E "(cores|memory|work-stealing)" /etc/meteor/meteor.conf

# Monitor process
top -p $(pgrep meteor-server)
```

**Connection refused**
```bash
# Check if service is running
sudo systemctl status meteor

# Check port binding
sudo netstat -tlnp | grep 6379

# Test connectivity
telnet 127.0.0.1 6379
```

### Log Locations
- **Service logs**: `journalctl -u meteor`
- **Application logs**: `/var/log/meteor/meteor.log`
- **Backup logs**: `/var/log/meteor/backup.log`
- **System logs**: `/var/log/syslog` or `/var/log/messages`

## 📞 Support

### Performance Tuning
For production workloads, consider:
- NUMA topology optimization
- CPU governor settings (performance mode)
- Network interface tuning
- Filesystem optimization (XFS recommended)
- Kernel parameters tuning

### Scaling Considerations
- Vertical scaling: Increase cores/memory
- Horizontal scaling: Multiple instances with load balancer
- Data partitioning: Shard-aware client routing
- Read replicas: For read-heavy workloads

## 📄 License

Enterprise deployment scripts are provided under the same license as the Meteor server.

---

For additional support and enterprise features, contact the Meteor development team.
