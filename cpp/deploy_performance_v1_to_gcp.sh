#!/bin/bash

echo "🚀 Deploying Meteor Performance V1 to GCP VM..."

# Create directory on GCP VM first
echo "📁 Creating directory on GCP VM..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="mkdir -p /tmp/meteor-perf-v1"

# Upload files to GCP VM
echo "📤 Uploading files to GCP VM..."
gcloud compute scp sharded_server_performance_v1.cpp mcache-ssd-tiering-lssd:/tmp/meteor-perf-v1/ --zone=asia-southeast1-a --project=<your-gcp-project-id>
gcloud compute scp build_performance_v1.sh mcache-ssd-tiering-lssd:/tmp/meteor-perf-v1/ --zone=asia-southeast1-a --project=<your-gcp-project-id>

# Build on GCP VM
echo "🔧 Building on GCP VM..."
gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
    cd /tmp/meteor-perf-v1
    chmod +x build_performance_v1.sh
    ./build_performance_v1.sh
"

if [ $? -eq 0 ]; then
    echo "✅ Build successful on GCP VM!"
    echo ""
    echo "🧪 Testing basic functionality..."
    
    # Start server in background
    gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command="
        cd /tmp/meteor-perf-v1
        ./meteor-performance-v1 --port 6395 --enable-logging &
        sleep 3
        
        # Test basic commands
        echo 'Testing PING...'
        echo 'PING' | nc localhost 6395
        
        echo 'Testing SET...'
        echo -e '*3\r\n\$3\r\nSET\r\n\$8\r\ntest_key\r\n\$10\r\ntest_value\r\n' | nc localhost 6395
        
        echo 'Testing GET...'
        echo -e '*2\r\n\$3\r\nGET\r\n\$8\r\ntest_key\r\n' | nc localhost 6395
        
        # Kill server
        pkill -f meteor-performance-v1
        
        echo '✅ Basic functionality test completed!'
    "
    
    echo ""
    echo "🎯 Performance V1 deployed successfully!"
    echo "📍 Server binary: /tmp/meteor-perf-v1/meteor-performance-v1"
    echo ""
    echo "🚀 Ready to run performance tests!"
    echo ""
    echo "Next steps:"
    echo "1. Start server: gcloud compute ssh mcache-ssd-tiering-lssd --zone=asia-southeast1-a --project=<your-gcp-project-id> --command='cd /tmp/meteor-perf-v1 && ./meteor-performance-v1 --port 6395 --enable-logging'"
    echo "2. Run benchmarks against Redis and compare performance"
    echo "3. Test with high concurrency (200+ clients)"
else
    echo "❌ Build failed on GCP VM!"
    exit 1
fi 