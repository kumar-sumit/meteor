#!/bin/bash
# Quick monitoring script for persistence test

echo "🔍 MONITORING PERSISTENCE TEST ON mcache-lssd-sumit"
echo "===================================================="
echo ""

# Check if processes are running
echo "1️⃣ Process Status:"
gcloud compute ssh --zone "asia-southeast1-a" "mcache-lssd-sumit" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command="ps aux | grep -E 'meteor_redis.*6390|test_persistence' | grep -v grep | head -5"

echo ""
echo "2️⃣ Files Created:"
gcloud compute ssh --zone "asia-southeast1-a" "mcache-lssd-sumit" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command="cd /home/sumit.kumar/meteor-persistent-test && ls -lh test_snapshots/*.rdb 2>/dev/null || echo 'No RDB yet' && ls -lh test_aof/meteor.aof 2>/dev/null || echo 'No AOF yet'"

echo ""
echo "3️⃣ Server Logs (last 10 lines):"
gcloud compute ssh --zone "asia-southeast1-a" "mcache-lssd-sumit" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command="cd /home/sumit.kumar/meteor-persistent-test && tail -10 server.log 2>/dev/null || echo 'No logs yet'"

echo ""
echo "4️⃣ Test Completion Check:"
gcloud compute ssh --zone "asia-southeast1-a" "mcache-lssd-sumit" \
  --tunnel-through-iap --project "<your-gcp-project-id>" \
  --command="cd /home/sumit.kumar/meteor-persistent-test && if grep -q 'ALL TESTS PASSED' server*.log 2>/dev/null; then echo '✅ TEST COMPLETE!'; else echo '⏳ Still running...'; fi"

echo ""
echo "===================================================="
echo "To see full output when complete:"
echo "gcloud compute ssh mcache-lssd-sumit --zone asia-southeast1-a --project <your-gcp-project-id> --tunnel-through-iap --command='cat /home/sumit.kumar/meteor-persistent-test/server.log'"



