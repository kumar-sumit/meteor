#!/bin/bash

set -e

echo "🚀 Deploying Fixed Meteor Performance V2 Server to GCP..."

# Build and deploy to GCP
gcloud compute ssh mcache-ssd-tiering-lssd \
    --zone=asia-southeast1-a \
    --project=<your-gcp-project-id> \
    --command="
        # Create working directory
        mkdir -p /tmp/meteor-performance-v2-fixed
        cd /tmp/meteor-performance-v2-fixed
        
        # Clean up any existing processes
        pkill -f meteor-performance-v2-fixed || true
        
        # Remove old files
        rm -f meteor-performance-v2-fixed sharded_server_performance_v2_fixed.cpp
        
        echo '🔧 Building Fixed Meteor Performance V2 Server on GCP...'
    " && \

# Copy the fixed source code
gcloud compute scp cpp/sharded_server_performance_v2_fixed.cpp \
    mcache-ssd-tiering-lssd:/tmp/meteor-performance-v2-fixed/ \
    --zone=asia-southeast1-a \
    --project=<your-gcp-project-id> && \

# Build and run the server
gcloud compute ssh mcache-ssd-tiering-lssd \
    --zone=asia-southeast1-a \
    --project=<your-gcp-project-id> \
    --command="
        cd /tmp/meteor-performance-v2-fixed
        
        # Build with optimizations
        g++ -std=c++20 -O3 -DNDEBUG -pthread \
            -march=native \
            -flto \
            -fno-omit-frame-pointer \
            -o meteor-performance-v2-fixed \
            sharded_server_performance_v2_fixed.cpp \
            -luring 2>/dev/null || \
        g++ -std=c++20 -O3 -DNDEBUG -pthread \
            -march=native \
            -flto \
            -fno-omit-frame-pointer \
            -o meteor-performance-v2-fixed \
            sharded_server_performance_v2_fixed.cpp
        
        if [ -f meteor-performance-v2-fixed ]; then
            echo '✅ Build successful!'
            echo '📦 Binary size:' \$(du -h meteor-performance-v2-fixed | cut -f1)
            echo '🚀 Starting server...'
            
            # Start the server
            ./meteor-performance-v2-fixed --port 6382 --enable-logging
        else
            echo '❌ Build failed!'
            exit 1
        fi
    " 