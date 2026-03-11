#!/bin/bash

# Deploy Connection-Fixed Meteor Server to GCP VM
# This script builds and deploys the server with thread pool connection management

set -e

echo "🚀 Deploying Connection-Fixed Meteor Server to GCP VM..."

# Configuration
GCP_PROJECT="<your-gcp-project-id>"
GCP_ZONE="asia-southeast1-a"
GCP_INSTANCE="mcache-ssd-tiering-lssd"
REMOTE_DIR="/tmp/meteor-connection-fixed"
SERVER_PORT="6379"

# Files to deploy
SOURCE_FILE="sharded_server_dash_hash_hybrid_connection_fixed.cpp"
BUILD_SCRIPT="build_connection_fixed.sh"

echo "📋 Deployment Configuration:"
echo "  Project: $GCP_PROJECT"
echo "  Zone: $GCP_ZONE"
echo "  Instance: $GCP_INSTANCE"
echo "  Remote Directory: $REMOTE_DIR"
echo "  Server Port: $SERVER_PORT"
echo ""

# Check if source files exist
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Error: Source file '$SOURCE_FILE' not found!"
    exit 1
fi

if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "❌ Error: Build script '$BUILD_SCRIPT' not found!"
    exit 1
fi

echo "🔍 Checking GCP connectivity..."
if ! gcloud compute instances list --project=$GCP_PROJECT --zones=$GCP_ZONE --filter="name=$GCP_INSTANCE" --format="value(name)" | grep -q "$GCP_INSTANCE"; then
    echo "❌ Error: GCP instance '$GCP_INSTANCE' not found or not accessible!"
    exit 1
fi
echo "✅ GCP connectivity confirmed"

echo "📁 Creating remote directory..."
gcloud compute ssh $GCP_INSTANCE \
    --zone=$GCP_ZONE \
    --project=$GCP_PROJECT \
    --command="mkdir -p $REMOTE_DIR"

echo "📤 Copying source files..."
gcloud compute scp $SOURCE_FILE $GCP_INSTANCE:$REMOTE_DIR/ \
    --zone=$GCP_ZONE \
    --project=$GCP_PROJECT

gcloud compute scp $BUILD_SCRIPT $GCP_INSTANCE:$REMOTE_DIR/ \
    --zone=$GCP_ZONE \
    --project=$GCP_PROJECT

echo "🔧 Installing dependencies on remote server..."
gcloud compute ssh $GCP_INSTANCE \
    --zone=$GCP_ZONE \
    --project=$GCP_PROJECT \
    --command="sudo apt-get update && sudo apt-get install -y build-essential g++ cmake pkg-config liburing-dev"

echo "✅ Dependencies installed"

echo "🔨 Building server on remote machine..."
gcloud compute ssh $GCP_INSTANCE \
    --zone=$GCP_ZONE \
    --project=$GCP_PROJECT \
    --command="cd $REMOTE_DIR && chmod +x $BUILD_SCRIPT && ./$BUILD_SCRIPT"

echo "✅ Build successful on remote server!"

echo "🎯 Deployment completed successfully!"
echo ""
echo "🚀 To start the server, run:"
echo "  gcloud compute ssh $GCP_INSTANCE --zone=$GCP_ZONE --project=$GCP_PROJECT --command=\"cd $REMOTE_DIR && ./build/meteor-connection-fixed-server --port $SERVER_PORT --shards 8 --memory 128 --enable-logging --max-conn 500\""
echo ""
echo "🔧 Server configuration options:"
echo "  --port <port>          Server port (default: 6379)"
echo "  --shards <count>       Number of cache shards (default: CPU cores)"
echo "  --memory <MB>          Memory per shard in MB (default: 64)"
echo "  --ssd-path <path>      SSD storage path (optional)"
echo "  --enable-logging       Enable debug logging"
echo "  --max-conn <count>     Maximum connections (default: 1000)"
echo "  --enable-tiered        Enable tiered caching"
echo ""
echo "📊 To test the server:"
echo "  # Basic functionality"
echo "  redis-cli -h localhost -p $SERVER_PORT ping"
echo "  redis-cli -h localhost -p $SERVER_PORT set test_key test_value"
echo "  redis-cli -h localhost -p $SERVER_PORT get test_key"
echo ""
echo "  # Connection pool statistics"
echo "  redis-cli -h localhost -p $SERVER_PORT CONNSTATS"
echo ""
echo "  # Load testing"
echo "  redis-benchmark -h localhost -p $SERVER_PORT -c 100 -n 10000 -t set,get"
echo "  redis-benchmark -h localhost -p $SERVER_PORT -c 300 -n 30000 -t set,get"
echo ""
echo "🎉 Deployment complete! The connection-fixed server is ready for testing." 