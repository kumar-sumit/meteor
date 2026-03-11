#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🔍 BASELINE SERVER - PERSISTENT CONNECTION TEST"
echo "$(date): Testing baseline with persistent connections (like memtier)"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== STEP 1: START BASELINE SERVER ==="
echo "Starting original baseline server..."
nohup ./meteor_baseline_original -c 4 -s 4 > baseline_persistent.log 2>&1 &
SERVER_PID=$!
sleep 6

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    cat baseline_persistent.log
    exit 1
fi

echo "✅ BASELINE SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 2: PERSISTENT CONNECTION TEST ==="
echo "🎯 Testing with single persistent connection (like real Redis clients)"

# Create a persistent connection test file
cat > persistent_test_commands.txt << 'EOF'
*3
$3
SET
$4
key1
$6
value1
*2
$3
GET
$4
key1
*1
$4
PING
*3
$3
SET
$4
key2
$6
value2
*2
$3
GET
$4
key2
*3
$3
SET
$4
key3
$6
value3
*2
$3
GET
$4
key3
*1
$4
PING
*3
$3
SET
$4
key4
$10
longvalue4
*2
$3
GET
$4
key4
*2
$3
DEL
$4
key1
*2
$3
GET
$4
key1
*1
$4
PING
EOF

echo "Sending multiple commands through single persistent connection..."
PERSISTENT_RESULT=$(cat persistent_test_commands.txt | nc -w 10 127.0.0.1 6379)

echo "Persistent connection result:"
echo "$PERSISTENT_RESULT"

# Count successful operations
OK_COUNT=$(echo "$PERSISTENT_RESULT" | grep -c "+OK" || true)
PONG_COUNT=$(echo "$PERSISTENT_RESULT" | grep -c "+PONG" || true)
VALUE_COUNT=$(echo "$PERSISTENT_RESULT" | grep -c "value" || true)

echo ""
echo "=== STEP 3: RESULT ANALYSIS ==="
echo "Operations counted:"
echo "- SET operations (+OK): $OK_COUNT"
echo "- PING operations (+PONG): $PONG_COUNT" 
echo "- GET operations with values: $VALUE_COUNT"

PERSISTENT_SUCCESS=false
if [ "$OK_COUNT" -ge 4 ] && [ "$PONG_COUNT" -ge 3 ] && [ "$VALUE_COUNT" -ge 3 ]; then
    echo "✅ PERSISTENT CONNECTION SUCCESS: All operations working"
    PERSISTENT_SUCCESS=true
else
    echo "❌ PERSISTENT CONNECTION FAILED: Not all operations successful"
fi

echo ""
echo "=== STEP 4: MEMTIER-STYLE RAPID TEST ==="
echo "🎯 Testing rapid operations like memtier benchmark"

# Create rapid test commands
cat > rapid_test_commands.txt << 'EOF'
*3
$3
SET
$5
rapid1
$7
rvalue1
*3
$3
SET
$5
rapid2
$7
rvalue2
*3
$3
SET
$5
rapid3
$7
rvalue3
*2
$3
GET
$5
rapid1
*2
$3
GET
$5
rapid2
*2
$3
GET
$5
rapid3
*1
$4
PING
*1
$4
PING
*1
$4
PING
EOF

echo "Sending rapid commands through persistent connection..."
RAPID_RESULT=$(cat rapid_test_commands.txt | nc -w 5 127.0.0.1 6379)

echo "Rapid test result:"
echo "$RAPID_RESULT"

# Count rapid operations
RAPID_OK=$(echo "$RAPID_RESULT" | grep -c "+OK" || true)
RAPID_PONG=$(echo "$RAPID_RESULT" | grep -c "+PONG" || true)
RAPID_VALUES=$(echo "$RAPID_RESULT" | grep -c "rvalue" || true)

echo ""
echo "Rapid operations counted:"
echo "- SET operations (+OK): $RAPID_OK"  
echo "- PING operations (+PONG): $RAPID_PONG"
echo "- GET operations with values: $RAPID_VALUES"

RAPID_SUCCESS=false
if [ "$RAPID_OK" -ge 3 ] && [ "$RAPID_PONG" -ge 3 ] && [ "$RAPID_VALUES" -ge 3 ]; then
    echo "✅ RAPID TEST SUCCESS: All rapid operations working"
    RAPID_SUCCESS=true
else
    echo "❌ RAPID TEST FAILED: Rapid operations not all successful"
fi

echo ""
echo "=== STEP 5: PIPELINE TEST ==="
echo "🎯 Testing pipeline operations (multiple commands in one request)"

# Test actual pipeline (what the server is designed for)
cat > pipeline_test.txt << 'EOF'
*3
$3
SET
$4
pipe1
$6
pvalue1
*3
$3
SET
$4
pipe2
$6
pvalue2
*2
$3
GET
$4
pipe1
*2
$3
GET
$4
pipe2
*1
$4
PING
EOF

echo "Testing pipeline operations..."
PIPELINE_RESULT=$(cat pipeline_test.txt | nc -w 5 127.0.0.1 6379)

echo "Pipeline result:"
echo "$PIPELINE_RESULT"

PIPELINE_SUCCESS=false
if echo "$PIPELINE_RESULT" | grep -q "+OK" && echo "$PIPELINE_RESULT" | grep -q "pvalue" && echo "$PIPELINE_RESULT" | grep -q "+PONG"; then
    echo "✅ PIPELINE SUCCESS: Pipeline operations working"
    PIPELINE_SUCCESS=true
else
    echo "❌ PIPELINE FAILED: Pipeline operations not working"
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 BASELINE PERSISTENT CONNECTION ANALYSIS"
echo "=========================================="
echo ""

BASELINE_ACTUALLY_WORKS=false
if [ "$PERSISTENT_SUCCESS" = true ] && [ "$RAPID_SUCCESS" = true ] && [ "$PIPELINE_SUCCESS" = true ]; then
    BASELINE_ACTUALLY_WORKS=true
fi

if [ "$BASELINE_ACTUALLY_WORKS" = true ]; then
    echo "✅ BASELINE SERVER: ACTUALLY WORKS PERFECTLY! ✅"
    echo ""
    echo "🎯 CORRECTED UNDERSTANDING:"
    echo "   • Baseline works fine with persistent connections"
    echo "   • Previous test used individual nc connections (wrong method)"
    echo "   • Server is designed for persistent connections like Redis"
    echo "   • memtier works because it uses proper persistent connections"
    echo ""
    echo "🔍 ROOT CAUSE OF TTL FAILURES:"
    echo "   • My TTL implementations have bugs independent of connection handling"
    echo "   • Need to identify what changes in my TTL code break functionality"
    echo "   • Response handling issue is in my modifications, not baseline"
    echo ""
    echo "📋 CORRECT NEXT STEPS:"
    echo "   1. Baseline is fine - focus on TTL implementation bugs"
    echo "   2. Test my TTL implementations with persistent connections"
    echo "   3. Find the specific TTL code change that breaks responses"
    echo "   4. Fix TTL implementation without breaking persistent connection handling"
else
    echo "⚠️  BASELINE SERVER: STILL HAS SOME ISSUES"
    echo ""
    echo "🔍 PERSISTENT CONNECTION RESULTS:"
    if [ "$PERSISTENT_SUCCESS" = false ]; then
        echo "   • Basic persistent connections not working properly"
    fi
    if [ "$RAPID_SUCCESS" = false ]; then
        echo "   • Rapid operations through persistent connections failing"
    fi
    if [ "$PIPELINE_SUCCESS" = false ]; then
        echo "   • Pipeline operations not working"
    fi
fi

echo ""
echo "$(date): Baseline persistent connection test complete!"
echo ""

echo "Server log (last 15 lines):"
tail -15 baseline_persistent.log

echo ""
if [ "$BASELINE_ACTUALLY_WORKS" = true ]; then
    echo "🎉 BASELINE IS FINE! ISSUE IS IN MY TTL IMPLEMENTATIONS! 🎉"
else
    echo "🔧 NEED TO INVESTIGATE BASELINE CONNECTION HANDLING"
fi

# Cleanup
rm -f persistent_test_commands.txt rapid_test_commands.txt pipeline_test.txt












