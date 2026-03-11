#!/bin/bash

echo "🚀 DEPLOYING PHASE 5 STEP 4A TO MCACHE-SSD-TIERING-POC VM"
echo "========================================================="
echo "Target VM: mcache-ssd-tiering-poc"
echo "Target IP: 172.23.72.71"
echo "Benchmark from: memtier-benchmarking VM"
echo

# Copy Phase 5 source and build script to mcache VM
echo "📂 Copying Phase 5 source files to mcache VM..."
gcloud compute scp --zone "asia-southeast1-a" --tunnel-through-iap --project "<your-gcp-project-id>" \
    ~/meteor/sharded_server_phase5_step4a_simd_lockfree_monitoring.cpp \
    mcache-ssd-tiering-poc:~/

echo "📂 Creating build script on mcache VM..."
gcloud compute ssh --zone "asia-southeast1-a" "mcache-ssd-tiering-poc" --tunnel-through-iap --project "<your-gcp-project-id>" --command='
echo "🔧 Creating Phase 5 build script..."
cat > ~/build_phase5_mcache.sh << '"'"'EOF'"'"'
#!/bin/bash

echo "🚀 BUILDING PHASE 5 STEP 4A ON MCACHE VM"
echo "========================================"
echo "VM: mcache-ssd-tiering-poc"
echo "IP: 172.23.72.71"
echo

# Install dependencies if needed
echo "📦 Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y build-essential g++ libnuma-dev

echo "🔧 Compiling Phase 5 Step 4A..."
g++ -std=c++17 -O3 -march=native \
    -mavx2 -mfma -mbmi2 -mlzcnt \
    -pthread -lnuma \
    -DUSE_SIMD -DUSE_LOCKFREE -DUSE_MONITORING \
    -o meteor_phase5_step4a_mcache \
    sharded_server_phase5_step4a_simd_lockfree_monitoring.cpp

if [ $? -eq 0 ]; then
    echo "✅ Phase 5 compiled successfully!"
    echo "📊 Binary info:"
    ls -la meteor_phase5_step4a_mcache
    echo
    echo "🔧 Testing binary..."
    ./meteor_phase5_step4a_mcache --help || echo "Binary created successfully"
else
    echo "❌ Compilation failed!"
    exit 1
fi

echo "✅ Phase 5 ready for deployment on mcache VM"
EOF

chmod +x ~/build_phase5_mcache.sh
echo "✅ Build script created"
'

echo "🔧 Building Phase 5 on mcache VM..."
gcloud compute ssh --zone "asia-southeast1-a" "mcache-ssd-tiering-poc" --tunnel-through-iap --project "<your-gcp-project-id>" --command='
cd ~ && ./build_phase5_mcache.sh
'

echo "✅ Phase 5 deployment to mcache VM completed"