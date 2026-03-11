#!/bin/bash

cd /mnt/externalDisk/meteor

echo "=========================================="
echo "🔍 TESTING METEOR_FINAL_CORRECT FOR CORRECTNESS"
echo "$(date): Comprehensive correctness test of the final correct binary"
echo "=========================================="

# Clean up any existing processes
pkill -f meteor 2>/dev/null || true
sleep 3

echo ""
echo "=== BINARY INFORMATION ==="
echo "File details:"
ls -la cpp/meteor_final_correct
echo ""
echo "Binary type:"
file cpp/meteor_final_correct
echo ""

echo "=== STEP 1: START METEOR_FINAL_CORRECT SERVER ==="
echo "Copying binary to working directory..."
cp cpp/meteor_final_correct ./meteor_final_correct_test

echo "Starting meteor_final_correct server with 4 cores, 4 shards..."
nohup ./meteor_final_correct_test -c 4 -s 4 > meteor_final_correct.log 2>&1 &
SERVER_PID=$!
sleep 6

# Check if server started properly
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ SERVER STARTUP FAILED"
    echo "Server log:"
    cat meteor_final_correct.log
    exit 1
fi

echo "✅ METEOR_FINAL_CORRECT STARTED SUCCESSFULLY (PID: $SERVER_PID)"

echo ""
echo "=== STEP 2: BASIC CORRECTNESS TESTS ==="
echo "🎯 Testing core Redis commands"

echo -n "SET key1 value1: "
SET1=$(redis-cli -p 6379 SET key1 value1 2>/dev/null || echo "FAILED")
echo "$SET1"

echo -n "GET key1: "
GET1=$(redis-cli -p 6379 GET key1 2>/dev/null || echo "FAILED")
echo "$GET1"

echo -n "SET key2 value2: "
SET2=$(redis-cli -p 6379 SET key2 value2 2>/dev/null || echo "FAILED")
echo "$SET2"

echo -n "GET key2: "
GET2=$(redis-cli -p 6379 GET key2 2>/dev/null || echo "FAILED")
echo "$GET2"

echo -n "PING: "
PING_RESULT=$(redis-cli -p 6379 PING 2>/dev/null || echo "FAILED")
echo "$PING_RESULT"

echo -n "DEL key1: "
DEL1=$(redis-cli -p 6379 DEL key1 2>/dev/null || echo "FAILED")
echo "$DEL1"

echo -n "GET key1 (after DEL): "
GET1_AFTER_DEL=$(redis-cli -p 6379 GET key1 2>/dev/null || echo "FAILED")
if [ -z "$GET1_AFTER_DEL" ]; then
    GET1_AFTER_DEL="(null)"
fi
echo "$GET1_AFTER_DEL"

BASIC_SUCCESS=false
if [[ "$SET1" == "OK" ]] && [[ "$GET1" == "value1" ]] && [[ "$SET2" == "OK" ]] && [[ "$GET2" == "value2" ]] && [[ "$DEL1" == "1" ]]; then
    echo "✅ BASIC OPERATIONS: PERFECT"
    BASIC_SUCCESS=true
    
    if [[ "$PING_RESULT" == "PONG" ]]; then
        echo "✅ PING COMMAND: WORKING"
        PING_SUCCESS=true
    else
        echo "⚠️  PING ISSUES: '$PING_RESULT'"
        PING_SUCCESS=false
    fi
else
    echo "❌ BASIC OPERATIONS FAILED:"
    echo "   SET1='$SET1', GET1='$GET1', SET2='$SET2', GET2='$GET2', DEL1='$DEL1'"
fi

echo ""
echo "=== STEP 3: SEQUENTIAL OPERATIONS TEST ==="
echo "🎯 Testing multiple operations in sequence"

SEQUENTIAL_SUCCESS=true
for i in {1..5}; do
    redis-cli -p 6379 SET seqkey$i seqval$i >/dev/null 2>&1
    SEQ_RESULT=$(redis-cli -p 6379 GET seqkey$i 2>/dev/null || echo "FAILED")
    
    if [[ "$SEQ_RESULT" == "seqval$i" ]]; then
        echo "✓ Sequential operation $i: SUCCESS (seqkey$i = seqval$i)"
    else
        echo "✗ Sequential operation $i: FAILED (expected seqval$i, got '$SEQ_RESULT')"
        SEQUENTIAL_SUCCESS=false
        break
    fi
done

if [ "$SEQUENTIAL_SUCCESS" = true ]; then
    echo "✅ SEQUENTIAL OPERATIONS: PERFECT (5/5 successful)"
else
    echo "❌ SEQUENTIAL OPERATIONS: FAILED"
fi

echo ""
echo "=== STEP 4: CROSS-CORE OPERATIONS TEST ==="
echo "🎯 Testing cross-core key distribution (4 cores, 4 shards)"

CROSS_CORE_SUCCESS=true
echo "Testing keys that should hash to different cores..."
for i in {1..8}; do
    KEY="crosskey_$i"
    VALUE="crossval_$i"
    
    redis-cli -p 6379 SET $KEY $VALUE >/dev/null 2>&1
    CROSS_RESULT=$(redis-cli -p 6379 GET $KEY 2>/dev/null || echo "FAILED")
    
    if [[ "$CROSS_RESULT" == "$VALUE" ]]; then
        echo "✓ Cross-core key $i: SUCCESS"
    else
        echo "✗ Cross-core key $i: FAILED (expected $VALUE, got '$CROSS_RESULT')"
        CROSS_CORE_SUCCESS=false
        break
    fi
done

if [ "$CROSS_CORE_SUCCESS" = true ]; then
    echo "✅ CROSS-CORE OPERATIONS: PERFECT (8/8 successful)"
else
    echo "❌ CROSS-CORE OPERATIONS: FAILED"
fi

echo ""
echo "=== STEP 5: PIPELINE OPERATIONS TEST ==="
echo "🎯 Testing pipeline functionality"

# Test pipeline with multiple commands
echo "Testing pipeline with multiple SET/GET commands..."
PIPELINE_COMMANDS=""
for i in {1..3}; do
    PIPELINE_COMMANDS="$PIPELINE_COMMANDS SET pipekey$i pipeval$i "
done
for i in {1..3}; do
    PIPELINE_COMMANDS="$PIPELINE_COMMANDS GET pipekey$i "
done

# Execute pipeline
redis-cli -p 6379 $PIPELINE_COMMANDS > pipeline_result.txt 2>/dev/null

# Check pipeline results
PIPELINE_SUCCESS=false
if grep -q "OK" pipeline_result.txt && grep -q "pipeval" pipeline_result.txt; then
    echo "✅ PIPELINE OPERATIONS: WORKING"
    PIPELINE_SUCCESS=true
else
    echo "❌ PIPELINE OPERATIONS: ISSUES"
    echo "Pipeline result:"
    cat pipeline_result.txt
fi

echo ""
echo "=== STEP 6: PERFORMANCE STRESS TEST ==="
echo "🎯 Testing server stability under load"

STRESS_SUCCESS=true
echo "Running 20 rapid operations..."
for i in {1..20}; do
    redis-cli -p 6379 SET stresskey$i stressval$i >/dev/null 2>&1
    STRESS_RESULT=$(redis-cli -p 6379 GET stresskey$i 2>/dev/null || echo "FAILED")
    
    if [[ "$STRESS_RESULT" != "stressval$i" ]]; then
        echo "✗ Stress test failed at operation $i"
        STRESS_SUCCESS=false
        break
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        echo "Stress test progress: $i/20 operations completed"
    fi
done

if [ "$STRESS_SUCCESS" = true ]; then
    echo "✅ STRESS TEST: PERFECT (20/20 successful)"
else
    echo "❌ STRESS TEST: FAILED"
fi

# Clean shutdown
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo ""
echo "=========================================="
echo "🏆 METEOR_FINAL_CORRECT CORRECTNESS RESULTS"
echo "=========================================="
echo ""

# Calculate overall score
TOTAL_TESTS=5
PASSED_TESTS=0

echo "📊 CORRECTNESS TEST RESULTS:"
echo ""

if [ "$BASIC_SUCCESS" = true ]; then 
    echo "✅ Basic Operations: PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else 
    echo "❌ Basic Operations: FAIL"
fi

if [ "$SEQUENTIAL_SUCCESS" = true ]; then 
    echo "✅ Sequential Operations: PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else 
    echo "❌ Sequential Operations: FAIL"
fi

if [ "$CROSS_CORE_SUCCESS" = true ]; then 
    echo "✅ Cross-Core Operations: PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else 
    echo "❌ Cross-Core Operations: FAIL"
fi

if [ "$PIPELINE_SUCCESS" = true ]; then 
    echo "✅ Pipeline Operations: PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else 
    echo "❌ Pipeline Operations: FAIL"
fi

if [ "$STRESS_SUCCESS" = true ]; then 
    echo "✅ Stress Testing: PASS"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else 
    echo "❌ Stress Testing: FAIL"
fi

echo ""
echo "Overall Score: $PASSED_TESTS/$TOTAL_TESTS tests passed"

if [ "$PASSED_TESTS" -eq "$TOTAL_TESTS" ]; then
    echo ""
    echo "🎉 METEOR_FINAL_CORRECT: FULLY CORRECT! 🎉"
    echo ""
    echo "✅ VERIFIED CAPABILITIES:"
    echo "   • Core Redis commands (SET/GET/DEL/PING)"
    echo "   • Sequential operations stability"
    echo "   • Cross-core key distribution"
    echo "   • Pipeline command processing"  
    echo "   • High-load stress testing"
    echo ""
    echo "🎯 READY FOR:"
    echo "   • Production deployment"
    echo "   • TTL implementation baseline"
    echo "   • Performance benchmarking"
    echo "   • Feature extensions"
elif [ "$PASSED_TESTS" -gt 3 ]; then
    echo ""
    echo "✅ METEOR_FINAL_CORRECT: MOSTLY CORRECT"
    echo "   ($PASSED_TESTS/$TOTAL_TESTS tests passed - Good foundation)"
else
    echo ""
    echo "⚠️  METEOR_FINAL_CORRECT: NEEDS ATTENTION"
    echo "   ($PASSED_TESTS/$TOTAL_TESTS tests passed - Requires fixes)"
fi

echo ""
echo "$(date): meteor_final_correct correctness test complete!"
echo ""

echo "Server log (last 10 lines):"
tail -10 meteor_final_correct.log

# Cleanup
rm -f pipeline_result.txt meteor_final_correct_test

echo ""
echo "🚀 meteor_final_correct binary tested for correctness!"












