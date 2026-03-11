#!/bin/bash
# Build and test Meteor package directly on mcache-lssd-sumit VM

set -euo pipefail

PROJECT="<your-gcp-project-id>"
ZONE="asia-southeast1-a"
VM="mcache-lssd-sumit"

echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║      Build & Test Meteor Package on mcache-lssd-sumit VM                ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Transfer source files to VM
echo "📤 Step 1: Transferring source files to VM..."

# Create list of files to transfer
FILES_TO_TRANSFER=(
    "cpp/meteor_redis_client_compatible_with_persistence.cpp"
    "cpp/meteor_persistence_module.hpp"
    "create_meteor_package.sh"
    "deployment/scripts/deploy_meteor.sh"
    "deployment/systemd/meteor.service"
    "deployment/config/production.conf"
    "deployment/monitoring"
)

# Transfer files
for file in "${FILES_TO_TRANSFER[@]}"; do
    if [ -e "$file" ]; then
        echo "  Transferring: $file"
        gcloud compute scp --recurse "$file" "$VM:/tmp/meteor-build/" \
            --project="$PROJECT" \
            --zone="$ZONE" \
            --quiet 2>/dev/null || true
    fi
done

echo "✅ Source files transferred"
echo ""

# Step 2: Build package on VM
echo "🔧 Step 2: Building package on VM..."
gcloud compute ssh "$VM" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --command="
set -e

echo '📦 Preparing build environment...'
cd /tmp/meteor-build

# Create deployment directory structure if needed
mkdir -p deployment/scripts deployment/systemd deployment/config deployment/monitoring
touch deployment/monitoring/.gitkeep

# Make script executable
chmod +x create_meteor_package.sh

echo ''
echo '🔨 Building package with persistence source...'
./create_meteor_package.sh --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp 2>&1 | tail -30

# Find created package
PACKAGE=\$(ls -t meteor-server-*.tar.gz 2>/dev/null | head -1)
if [ -z \"\$PACKAGE\" ]; then
    echo '❌ Package not created!'
    exit 1
fi

echo ''
echo '✅ Package built successfully:'
ls -lh \"\$PACKAGE\"
echo ''

# Extract package
echo '📦 Extracting package...'
tar -xzf \"\$PACKAGE\"
PACKAGE_DIR=\$(ls -td meteor-server-*/ | head -1)
cd \"\$PACKAGE_DIR\"

echo ''
echo '📂 Package contents:'
echo '==================='
echo 'Binaries:'
ls -lh bin/
echo ''
echo 'Scripts:'
ls -lh scripts/
echo ''
echo 'Config templates:'
ls -lh etc/
echo ''
echo 'Systemd services:'
ls -lh systemd/
"

echo "✅ Package built on VM"
echo ""

# Step 3: Install package
echo "🚀 Step 3: Installing package..."
gcloud compute ssh "$VM" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --command="
set -e
cd /tmp/meteor-build

# Find package directory
PACKAGE_DIR=\$(ls -td meteor-server-*/ | head -1)
cd \"\$PACKAGE_DIR\"

echo '🔧 Installing Meteor server with persistence...'
echo 'Configuration:'
echo '  - Cores: 4'
echo '  - Shards: 4'
echo '  - Memory: 16GB'
echo '  - Persistence: Enabled'
echo '  - Snapshot interval: 30 minutes'
echo ''

sudo ./install.sh \
    --cores 4 \
    --shards 4 \
    --memory 16384 \
    --persistence 1 \
    --snapshot-interval 1800 \
    --fsync-policy 2

echo ''
echo '✅ Installation complete!'
"

echo ""
echo "🔍 Step 4: Verifying installation..."
gcloud compute ssh "$VM" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --command="
echo '╔══════════════════════════════════════════════════════════════════════════╗'
echo '║                        Installation Verification                         ║'
echo '╚══════════════════════════════════════════════════════════════════════════╝'
echo ''

echo '1️⃣  Service Status:'
echo '==================='
systemctl is-active meteor.service && echo '✅ meteor.service: ACTIVE' || echo '❌ meteor.service: INACTIVE'
systemctl is-active meteor-health-monitor.service && echo '✅ health-monitor: ACTIVE' || echo '❌ health-monitor: INACTIVE'
systemctl is-active meteor-hangdetector.timer && echo '✅ hangdetector timer: ACTIVE' || echo '❌ hangdetector timer: INACTIVE'
echo ''

echo '2️⃣  Configuration File:'
echo '==================='
echo 'Health Monitor Settings:'
cat /etc/meteor/meteor.conf | grep METEOR_HEALTH
echo ''
echo 'Hang Detector Settings:'
cat /etc/meteor/meteor.conf | grep METEOR_HANG
echo ''

echo '3️⃣  Monitoring Scripts:'
echo '==================='
ls -lh /opt/meteor/scripts/meteor-health-monitor.sh 2>/dev/null && echo '✅ health-monitor.sh exists' || echo '❌ health-monitor.sh missing'
ls -lh /opt/meteor/scripts/meteor-hangdetector.sh 2>/dev/null && echo '✅ hangdetector.sh exists' || echo '❌ hangdetector.sh missing'
echo ''

echo '4️⃣  Systemd Services:'
echo '==================='
ls -lh /etc/systemd/system/meteor-health-monitor.service 2>/dev/null && echo '✅ health-monitor.service' || echo '❌ health-monitor.service missing'
ls -lh /etc/systemd/system/meteor-hangdetector.service 2>/dev/null && echo '✅ hangdetector.service' || echo '❌ hangdetector.service missing'
ls -lh /etc/systemd/system/meteor-hangdetector.timer 2>/dev/null && echo '✅ hangdetector.timer' || echo '❌ hangdetector.timer missing'
echo ''

echo '5️⃣  Log Files:'
echo '==================='
if [ -f /var/log/meteor/health-monitor.log ]; then
    echo 'Health Monitor Log (last 5 lines):'
    sudo tail -5 /var/log/meteor/health-monitor.log
else
    echo '⚠️  Health monitor log not created yet'
fi
echo ''

if [ -f /var/log/meteor/hang-detector.log ]; then
    echo 'Hang Detector Log (last 5 lines):'
    sudo tail -5 /var/log/meteor/hang-detector.log
else
    echo '⚠️  Hang detector log not created yet'
fi
echo ''

echo '6️⃣  Redis Connectivity Test:'
echo '==================='
if redis-cli -h 127.0.0.1 -p 6379 PING 2>/dev/null | grep -q PONG; then
    echo '✅ Server responding to PING'
    
    # Test SET and GET
    redis-cli -h 127.0.0.1 -p 6379 SET test_key test_value >/dev/null 2>&1
    RESULT=\$(redis-cli -h 127.0.0.1 -p 6379 GET test_key 2>/dev/null)
    if [ \"\$RESULT\" = \"test_value\" ]; then
        echo '✅ SET/GET working correctly'
    else
        echo '❌ SET/GET not working'
    fi
else
    echo '❌ Server not responding'
fi
echo ''

echo '7️⃣  Persistence Directories:'
echo '==================='
ls -ld /var/lib/meteor/snapshots 2>/dev/null && echo '✅ RDB directory exists' || echo '❌ RDB directory missing'
ls -ld /var/lib/meteor/aof 2>/dev/null && echo '✅ AOF directory exists' || echo '❌ AOF directory missing'
echo ''
"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                            Test Complete!                                ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "🧪 To test hang detection, run:"
echo ""
echo "   gcloud compute ssh $VM --project=$PROJECT --zone=$ZONE"
echo ""
echo "   # Kill the server to simulate hang"
echo "   sudo pkill -9 -f meteor-server"
echo ""
echo "   # Watch health monitor detect and restart (should restart in ~10 seconds)"
echo "   sudo tail -f /var/log/meteor/health-monitor.log"
echo ""
echo "   # Watch hang detector (backup, checks every 5 seconds)"
echo "   sudo tail -f /var/log/meteor/hang-detector.log"
echo ""
echo "   # Verify auto-restart worked"
echo "   redis-cli -h 127.0.0.1 -p 6379 PING"
echo ""


