#!/bin/bash
# Simple Performance Comparison: Step 1 Enhanced vs Step 3 Migration

echo "🔬 Quick Performance Comparison"
echo "==============================="

cd ~/meteor

# Kill any existing servers
pkill -f meteor_phase5 2>/dev/null || true
sleep 2

# Test Step 1 Enhanced on port 6380
echo "🚀 Testing Step 1 Enhanced (Direct Processing) on port 6380..."
nohup ./meteor_phase5_step1_enhanced -c 16 -s 16 -p 6380 > server_step1.log 2>&1 &
STEP1_PID=$!
sleep 3

if kill -0 $STEP1_PID 2>/dev/null; then
    echo "✅ Step 1 server started successfully"
    memtier_benchmark -s localhost -p 6380 -c 5 -t 2 --ratio=1:1 --test-time=30 -d 512 --hide-histogram > step1_results.log 2>&1
    echo "📊 Step 1 Results:"
    grep "Totals" step1_results.log | head -1
    kill $STEP1_PID 2>/dev/null || true
else
    echo "❌ Step 1 server failed to start"
fi

sleep 3

# Test Step 3 Migration on port 6381  
echo ""
echo "🚀 Testing Step 3 Migration (Connection Migration) on port 6381..."
nohup ./meteor_phase5_step3_migration -c 16 -s 16 -p 6381 > server_step3.log 2>&1 &
STEP3_PID=$!
sleep 3

if kill -0 $STEP3_PID 2>/dev/null; then
    echo "✅ Step 3 server started successfully"
    memtier_benchmark -s localhost -p 6381 -c 5 -t 2 --ratio=1:1 --test-time=30 -d 512 --hide-histogram > step3_results.log 2>&1
    echo "📊 Step 3 Results:"
    grep "Totals" step3_results.log | head -1
    kill $STEP3_PID 2>/dev/null || true
else
    echo "❌ Step 3 server failed to start"
fi

echo ""
echo "📋 Detailed logs:"
echo "   Step 1 server: server_step1.log"
echo "   Step 1 benchmark: step1_results.log"
echo "   Step 3 server: server_step3.log"
echo "   Step 3 benchmark: step3_results.log"