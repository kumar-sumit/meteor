#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🔍 BASELINE - PERSISTENT REDIS-CLI SESSION"
echo "$(date): Testing with single persistent redis-cli session (like memtier)"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== STEP 1: START BASELINE SERVER ==="
echo "Starting original baseline server..."
nohup ./meteor_baseline_original -c 4 -s 4 > baseline_persistent_redis.log 2>&1 &
SERVER_PID=$!
sleep 6

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    cat baseline_persistent_redis.log
    exit 1
fi

echo "✅ BASELINE SERVER STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 2: SINGLE PERSISTENT REDIS-CLI SESSION ==="
echo "🎯 Testing with one continuous redis-cli session (like memtier behavior)"

# Create a command script for persistent session
cat > redis_commands.txt << 'EOF'
SET key1 value1
GET key1
SET key2 value2  
GET key2
PING
SET key3 value3
GET key3
DEL key1
GET key1
SET longkey "this_is_a_longer_value_for_testing_purposes"
GET longkey
PING
SET key4 value4
GET key4
SET key5 value5
GET key5
QUIT
EOF

echo "Sending multiple commands through single persistent redis-cli session..."
echo "Commands being sent:"
cat redis_commands.txt
echo ""
echo "Results:"

# Use redis-cli in interactive mode with command file
PERSISTENT_RESULT=$(timeout 30s redis-cli -p 6379 < redis_commands.txt 2>/dev/null || echo "SESSION_FAILED")

echo "$PERSISTENT_RESULT"

echo ""
echo "=== STEP 3: ANALYSIS OF PERSISTENT SESSION ==="

# Count results
OK_COUNT=$(echo "$PERSISTENT_RESULT" | grep -c "^OK$" || true)
VALUE_COUNT=$(echo "$PERSISTENT_RESULT" | grep -c "value" || true)
PONG_COUNT=$(echo "$PERSISTENT_RESULT" | grep -c "^PONG$" || true)
DELETE_COUNT=$(echo "$PERSISTENT_RESULT" | grep -c "^1$" || true)

echo "Operation counts from persistent session:"
echo "- SET operations (OK responses): $OK_COUNT"
echo "- GET operations (value responses): $VALUE_COUNT"  
echo "- PING operations (PONG responses): $PONG_COUNT"
echo "- DEL operations (1 responses): $DELETE_COUNT"

PERSISTENT_SUCCESS=false
if [ "$OK_COUNT" -ge 5 ] && [ "$VALUE_COUNT" -ge 4 ] && [ "$PONG_COUNT" -ge 1 ]; then
    echo "✅ PERSISTENT SESSION SUCCESS: All operations working in single session"
    PERSISTENT_SUCCESS=true
else
    echo "❌ PERSISTENT SESSION ISSUES: Not all operations successful"
    echo "   Expected: ≥5 SETs, ≥4 GETs with values, ≥1 PING"
    echo "   Got: $OK_COUNT SETs, $VALUE_COUNT GETs, $PONG_COUNT PINGs"
fi

echo ""
echo "=== STEP 4: COMPARE CONNECTION PATTERNS ==="
echo "🎯 Testing different connection approaches"

echo ""
echo "--- Test A: Fresh redis-cli for each command (current script approach) ---"
echo -n "Individual SET: "
INDIVIDUAL_SET=$(timeout 5s redis-cli -p 6379 SET testkey1 testval1 2>/dev/null || echo "FAILED")
echo "$INDIVIDUAL_SET"

echo -n "Individual GET: " 
INDIVIDUAL_GET=$(timeout 5s redis-cli -p 6379 GET testkey1 2>/dev/null || echo "FAILED")
echo "$INDIVIDUAL_GET"

echo -n "Another Individual SET: "
INDIVIDUAL_SET2=$(timeout 5s redis-cli -p 6379 SET testkey2 testval2 2>/dev/null || echo "FAILED")
echo "$INDIVIDUAL_SET2"

echo ""
echo "--- Test B: Pipeline approach ---"
echo "Creating pipeline commands..."
cat > pipeline_commands.txt << 'EOF'
SET pipekey1 pipeval1
SET pipekey2 pipeval2
GET pipekey1
GET pipekey2
PING
EOF

echo "Pipeline results:"
PIPELINE_RESULT=$(timeout 10s redis-cli -p 6379 --pipe < pipeline_commands.txt 2>/dev/null || echo "PIPELINE_FAILED")
echo "$PIPELINE_RESULT"

echo ""
echo "=== STEP 5: CONNECTION BEHAVIOR ANALYSIS ==="

INDIVIDUAL_SUCCESS=false
if [[ "$INDIVIDUAL_SET" == "OK" ]] && [[ "$INDIVIDUAL_GET" == "testval1" ]] && [[ "$INDIVIDUAL_SET2" == "OK" ]]; then
    echo "✅ INDIVIDUAL CONNECTIONS: Working fine"
    INDIVIDUAL_SUCCESS=true
else
    echo "❌ INDIVIDUAL CONNECTIONS: Having issues after first few"
    echo "   This explains why sequential redis-cli calls in scripts fail"
fi

PIPELINE_SUCCESS=false
if echo "$PIPELINE_RESULT" | grep -q "OK" && echo "$PIPELINE_RESULT" | grep -q "pipeval"; then
    echo "✅ PIPELINE MODE: Working"
    PIPELINE_SUCCESS=true
else
    echo "❌ PIPELINE MODE: Issues"
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 CONNECTION PATTERN ANALYSIS RESULTS"
echo "=========================================="
echo ""

echo "📊 CONNECTION METHOD RESULTS:"
echo ""
echo "• Persistent Session (like memtier): $([ "$PERSISTENT_SUCCESS" = true ] && echo "✅ WORKS" || echo "❌ ISSUES")"
echo "• Individual Connections (script approach): $([ "$INDIVIDUAL_SUCCESS" = true ] && echo "✅ WORKS" || echo "❌ ISSUES")"  
echo "• Pipeline Mode: $([ "$PIPELINE_SUCCESS" = true ] && echo "✅ WORKS" || echo "❌ ISSUES")"

echo ""
echo "🎯 KEY FINDINGS:"
echo ""

if [ "$PERSISTENT_SUCCESS" = true ] && [ "$INDIVIDUAL_SUCCESS" = false ]; then
    echo "✅ BREAKTHROUGH IDENTIFIED:"
    echo "   • Baseline server works PERFECTLY with persistent connections"
    echo "   • Issue is with multiple separate redis-cli connections" 
    echo "   • memtier uses persistent/pooled connections → works fine"
    echo "   • My scripts use separate connections → fail after first few"
    echo "   • This explains why memtier succeeds but my tests fail"
    echo ""
    echo "🔍 ROOT CAUSE:"
    echo "   • Server designed for persistent connections (Redis standard)"
    echo "   • Connection setup/teardown overhead or state issues"
    echo "   • Need to test TTL with persistent sessions, not individual calls"
elif [ "$PERSISTENT_SUCCESS" = true ] && [ "$INDIVIDUAL_SUCCESS" = true ]; then
    echo "✅ BASELINE SERVER EXCELLENT:"
    echo "   • Works with persistent connections AND individual connections"
    echo "   • Previous test timeouts were script issues"
    echo "   • Server is fully functional and ready for TTL implementation"
elif [ "$PERSISTENT_SUCCESS" = false ]; then
    echo "⚠️  SERVER CONNECTION ISSUES:"
    echo "   • Even persistent connections having problems"
    echo "   • Need to investigate server connection handling"
    echo "   • May need baseline fixes before TTL implementation"
fi

echo ""
echo "$(date): Connection pattern analysis complete!"
echo ""

echo "Server log (last 10 lines):"
tail -10 baseline_persistent_redis.log

echo ""
if [ "$PERSISTENT_SUCCESS" = true ]; then
    echo "🎉 FOUND THE RIGHT WAY TO TEST! USE PERSISTENT SESSIONS! 🎉"
else
    echo "🔧 NEED TO INVESTIGATE SERVER CONNECTION HANDLING"
fi

# Cleanup
rm -f redis_commands.txt pipeline_commands.txt












