#!/bin/bash

set -e

echo "🚀 Deploying Fixed Meteor Server to GCP..."

# Build and deploy to GCP
gcloud compute ssh mcache-ssd-tiering-lssd \
    --zone=asia-southeast1-a \
    --project=<your-gcp-project-id> \
    --command="
        # Create working directory
        mkdir -p /tmp/meteor-fixed
        cd /tmp/meteor-fixed
        
        # Clean up any existing processes
        pkill -f meteor-sharded-server-fixed || true
        
        # Remove old files
        rm -f meteor-sharded-server-fixed sharded_server.cpp
        
        echo '🔧 Building Fixed Meteor Server on GCP...'
    " && \

# Copy the fixed source code
gcloud compute scp cpp/sharded_server.cpp \
    mcache-ssd-tiering-lssd:/tmp/meteor-fixed/ \
    --zone=asia-southeast1-a \
    --project=<your-gcp-project-id> && \

# Build and run on GCP
gcloud compute ssh mcache-ssd-tiering-lssd \
    --zone=asia-southeast1-a \
    --project=<your-gcp-project-id> \
    --command="
        cd /tmp/meteor-fixed
        
        # Build the server
        g++ -std=c++20 -O3 -DNDEBUG -pthread \
            -march=native \
            -flto \
            -fno-omit-frame-pointer \
            -o meteor-sharded-server-fixed \
            sharded_server.cpp \
            -luring 2>/dev/null || \
        g++ -std=c++20 -O3 -DNDEBUG -pthread \
            -march=native \
            -flto \
            -fno-omit-frame-pointer \
            -o meteor-sharded-server-fixed \
            sharded_server.cpp
        
        if [ -f meteor-sharded-server-fixed ]; then
            echo '✅ Build successful!'
            echo '📦 Binary size:' \$(du -h meteor-sharded-server-fixed | cut -f1)
            echo '🚀 Starting Fixed Meteor Server...'
            
            # Run the server
            ./meteor-sharded-server-fixed --port 6380 --shards 32 --enable-logging
        else
            echo '❌ Build failed!'
            exit 1
        fi
    "

echo "🎉 Deployment completed!" 