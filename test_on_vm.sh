#!/bin/bash
# Test script for mcache-lssd-sumit VM in <your-gcp-project-id> project

set -euo pipefail

PROJECT="<your-gcp-project-id>"
ZONE="asia-southeast1-a"
VM="mcache-lssd-sumit"

echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║         Testing Meteor Package on mcache-lssd-sumit VM                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Create package
echo "📦 Step 1: Creating package..."
if [ ! -f cpp/meteor_redis_client_compatible_with_persistence.cpp ]; then
    echo "❌ Source file not found!"
    exit 1
fi

# Create package
./create_meteor_package.sh --source-file cpp/meteor_redis_client_compatible_with_persistence.cpp 2>&1 | tail -20

# Find the created package
PACKAGE=$(ls -t meteor-server-*.tar.gz | head -1)
if [ -z "$PACKAGE" ]; then
    echo "❌ Package not created!"
    exit 1
fi

echo "✅ Package created: $PACKAGE"
PACKAGE_SIZE=$(du -h "$PACKAGE" | cut -f1)
echo "   Size: $PACKAGE_SIZE"
echo ""

# Step 2: Transfer to VM
echo "📤 Step 2: Transferring package to VM..."
gcloud compute scp "$PACKAGE" "$VM:/tmp/" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --quiet

echo "✅ Package transferred"
echo ""

# Step 3: SSH and install
echo "🚀 Step 3: Installing on VM..."
gcloud compute ssh "$VM" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --command="
set -e
cd /tmp

# Extract package
echo '📦 Extracting package...'
tar -xzf $PACKAGE
cd meteor-server-*

# Show package contents
echo '📂 Package contents:'
ls -la scripts/
echo ''

# Install
echo '🔧 Installing meteor server...'
sudo ./install.sh --cores 4 --shards 4 --memory 16384 --persistence 1

echo ''
echo '✅ Installation complete!'
"

echo ""
echo "🔍 Step 4: Verifying installation..."
gcloud compute ssh "$VM" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --command="
echo '📊 Service Status:'
echo '==================='
systemctl status meteor.service --no-pager | head -10
echo ''
systemctl status meteor-health-monitor.service --no-pager | head -10
echo ''
systemctl status meteor-hangdetector.timer --no-pager | head -10
echo ''

echo '📝 Configuration:'
echo '==================='
cat /etc/meteor/meteor.conf | grep -E 'HEALTH|HANG'
echo ''

echo '📂 Scripts:'
echo '==================='
ls -la /opt/meteor/scripts/*.sh
echo ''

echo '🔍 Health Monitor Logs (last 5 lines):'
echo '==================='
sudo tail -5 /var/log/meteor/health-monitor.log 2>/dev/null || echo 'No logs yet'
echo ''

echo '🧪 Testing Redis connectivity:'
echo '==================='
redis-cli -h 127.0.0.1 -p 6379 PING || echo 'Server not responding'
"

echo ""
echo "✅ All steps completed!"
echo ""
echo "🧪 To test hang detection, run on VM:"
echo "   gcloud compute ssh $VM --project=$PROJECT --zone=$ZONE"
echo "   sudo pkill -9 -f meteor-server"
echo "   sudo tail -f /var/log/meteor/health-monitor.log"
echo "   sudo tail -f /var/log/meteor/hang-detector.log"


