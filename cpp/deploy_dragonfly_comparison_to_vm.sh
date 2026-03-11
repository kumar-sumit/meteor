#!/bin/bash

echo "🚀 DEPLOYING DRAGONFLY COMPARISON TO VM"
echo "======================================"
echo "Target: memtier-benchmarking VM"
echo "Deploying comprehensive benchmark script and running comparison"
echo

# Upload the benchmark script to VM
echo "📂 Uploading benchmark script to VM..."
gcloud compute scp --zone "asia-southeast1-a" benchmark_phase5_vs_dragonfly_comprehensive.sh "memtier-benchmarking":~/ --project "<your-gcp-project-id>" --tunnel-through-iap

if [ $? -eq 0 ]; then
    echo "✅ Script uploaded successfully"
    
    echo "🚀 Running comprehensive benchmark on VM..."
    gcloud compute ssh --zone "asia-southeast1-a" "memtier-benchmarking" --tunnel-through-iap --project "<your-gcp-project-id>" --command='chmod +x ~/benchmark_phase5_vs_dragonfly_comprehensive.sh && ~/benchmark_phase5_vs_dragonfly_comprehensive.sh'
    
else
    echo "❌ Failed to upload script to VM"
    exit 1
fi