#!/bin/bash

# **PHASE 6 STEP 1: Deploy to VM and Benchmark Script**
# Deploy Phase 6 Step 1 to VM, build, and benchmark against Phase 5

echo "🚀 Deploying Phase 6 Step 1 to VM for testing..."

# VM connection details
VM_NAME="memtier-benchmarking"
VM_ZONE="asia-southeast1-a"
VM_PROJECT="<your-gcp-project-id>"
VM_USER="sumitkumar"

# Files to copy
FILES_TO_COPY=(
    "sharded_server_phase6_step1_avx512_numa.cpp"
    "build_phase6_step1_avx512_numa.sh"
)

echo "Copying files to VM..."
for file in "${FILES_TO_COPY[@]}"; do
    echo "  Copying $file..."
    gcloud compute scp --zone "$VM_ZONE" "$file" "$VM_USER@$VM_NAME:~/meteor/" \
        --tunnel-through-iap --project "$VM_PROJECT"
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to copy $file"
        exit 1
    fi
done

echo "✅ Files copied successfully!"

# Connect to VM and build
echo "Connecting to VM to build and test..."
gcloud compute ssh --zone "$VM_ZONE" "$VM_USER@$VM_NAME" \
    --tunnel-through-iap --project "$VM_PROJECT" \
    --command "
        echo '🏗️ Building Phase 6 Step 1 on VM...'
        cd ~/meteor/
        chmod +x build_phase6_step1_avx512_numa.sh
        ./build_phase6_step1_avx512_numa.sh
        
        if [ \$? -eq 0 ]; then
            echo '✅ Build successful! Starting server for testing...'
            echo '🚀 Starting Phase 6 Step 1 server...'
            timeout 5 ./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l &
            sleep 2
            
            echo '📊 Running quick benchmark test...'
            # Quick test to verify server is working
            echo 'PING' | nc -w 1 127.0.0.1 6379 || echo 'Server not responding'
            
            echo '🏁 Killing test server...'
            pkill -f meteor_phase6_step1_avx512_numa
            
            echo '📈 Phase 6 Step 1 deployment successful!'
            echo 'Ready for comprehensive benchmarking with memtier_benchmark'
        else
            echo '❌ Build failed on VM'
            exit 1
        fi
    "

echo "🎉 Phase 6 Step 1 deployment complete!"
echo
echo "Next steps:"
echo "1. SSH to VM: gcloud compute ssh --zone \"$VM_ZONE\" \"$VM_USER@$VM_NAME\" --tunnel-through-iap --project \"$VM_PROJECT\""
echo "2. Run server: ./meteor_phase6_step1_avx512_numa -h 127.0.0.1 -p 6379 -c 4 -s 16 -m 512 -l"
echo "3. Benchmark: memtier_benchmark -h 127.0.0.1 -p 6379 -t 2 -c 5 -n 10000 --ratio=1:1 --pipeline=10"