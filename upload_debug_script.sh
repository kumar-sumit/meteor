#!/bin/bash

echo "📤 Uploading debug script to VM..."

gcloud compute scp quick_ttl_debug.sh memtier-benchmarking:/mnt/externalDisk/meteor/ \
  --zone="asia-southeast1-a" --tunnel-through-iap --project="<your-gcp-project-id>"

echo ""  
echo "🔧 Now SSH to VM and run:"
echo "   gcloud compute ssh --zone=\"asia-southeast1-a\" \"memtier-benchmarking\" \\"
echo "     --tunnel-through-iap --project=\"<your-gcp-project-id>\""
echo ""
echo "   cd /mnt/externalDisk/meteor"
echo "   chmod +x quick_ttl_debug.sh"
echo "   ./quick_ttl_debug.sh"
echo ""
echo "This will show you exactly which test failed and why."













