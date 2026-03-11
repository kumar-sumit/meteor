#!/bin/bash

# **METEOR PIPELINE CORRECTNESS TEST**
# Tests 100 keys in pipeline mode with cross-shard validation
# Verifies that our pipeline correctness fix works properly

set -e

HOST=${1:-127.0.0.1}
PORT=${2:-6379}
NUM_KEYS=${3:-100}

echo "🚀 METEOR PIPELINE CORRECTNESS TEST"
echo "   Host: $HOST"
echo "   Port: $PORT" 
echo "   Keys: $NUM_KEYS"
echo ""

# Generate test data with cross-shard keys
echo "📝 Generating test data for cross-shard validation..."

# Create keys that will hash to different shards (4 shards, 6 total_shards in super_optimized)
KEYS=()
VALUES=()
for i in $(seq 1 $NUM_KEYS); do
    # Use different prefixes to ensure cross-shard distribution
    PREFIX=$(( i % 4 ))
    KEY="shard${PREFIX}_key_${i}_$(date +%s)"
    VALUE="value_${i}_$(openssl rand -hex 8)"
    KEYS+=("$KEY")  
    VALUES+=("$VALUE")
done

echo "✅ Generated $NUM_KEYS cross-shard test keys"

# Function to send pipeline commands
send_pipeline() {
    local commands="$1"
    echo -e "$commands" | nc -w 5 $HOST $PORT 2>/dev/null || {
        echo "❌ Failed to connect to server at $HOST:$PORT"
        return 1
    }
}

# Test 1: Pipeline SET commands
echo ""
echo "🔧 TEST 1: Pipeline SET commands"
SET_PIPELINE=""
for i in $(seq 0 $((NUM_KEYS-1))); do
    KEY="${KEYS[$i]}"
    VALUE="${VALUES[$i]}"
    # RESP protocol: *3\r\n$3\r\nSET\r\n$keylen\r\nkey\r\n$vallen\r\nvalue\r\n
    SET_PIPELINE+="*3\r\n\$3\r\nSET\r\n\$${#KEY}\r\n$KEY\r\n\$${#VALUE}\r\n$VALUE\r\n"
done

echo "   Sending $NUM_KEYS SET commands in single pipeline..."
SET_RESPONSE=$(send_pipeline "$SET_PIPELINE")

# Count successful SET responses (+OK)
SET_SUCCESS=$(echo "$SET_RESPONSE" | grep -c "+OK" || echo "0")
echo "   ✅ SET responses: $SET_SUCCESS/$NUM_KEYS successful"

if [ "$SET_SUCCESS" -ne "$NUM_KEYS" ]; then
    echo "   ❌ ERROR: Expected $NUM_KEYS +OK responses, got $SET_SUCCESS"
    echo "   Response preview:"
    echo "$SET_RESPONSE" | head -10
    exit 1
fi

# Wait for cross-shard propagation
sleep 1

# Test 2: Pipeline GET commands  
echo ""
echo "🔍 TEST 2: Pipeline GET commands"
GET_PIPELINE=""
for i in $(seq 0 $((NUM_KEYS-1))); do
    KEY="${KEYS[$i]}"
    # RESP protocol: *2\r\n$3\r\nGET\r\n$keylen\r\nkey\r\n
    GET_PIPELINE+="*2\r\n\$3\r\nGET\r\n\$${#KEY}\r\n$KEY\r\n"
done

echo "   Sending $NUM_KEYS GET commands in single pipeline..."
GET_RESPONSE=$(send_pipeline "$GET_PIPELINE")

# Parse and validate GET responses
echo "   🔍 Validating GET responses..."
IFS=$'\n' read -d '' -r -a RESPONSE_LINES <<< "$GET_RESPONSE" || true

CORRECT_RESPONSES=0
WRONG_RESPONSES=0
MISSING_RESPONSES=0

i=0
response_idx=0
while [ $i -lt $NUM_KEYS ] && [ $response_idx -lt ${#RESPONSE_LINES[@]} ]; do
    EXPECTED_VALUE="${VALUES[$i]}"
    KEY="${KEYS[$i]}"
    
    # Parse RESP response: $len\r\nvalue\r\n or $-1\r\n for null
    RESP_LINE="${RESPONSE_LINES[$response_idx]}"
    
    if [[ "$RESP_LINE" =~ ^\$-1 ]]; then
        echo "   ❌ Key $KEY: Missing (got \$-1)"
        ((MISSING_RESPONSES++))
        ((response_idx++))
    elif [[ "$RESP_LINE" =~ ^\$([0-9]+) ]]; then
        VALUE_LEN="${BASH_REMATCH[1]}"
        ((response_idx++))
        
        if [ $response_idx -lt ${#RESPONSE_LINES[@]} ]; then
            ACTUAL_VALUE="${RESPONSE_LINES[$response_idx]}"
            ((response_idx++))
            
            if [ "$ACTUAL_VALUE" = "$EXPECTED_VALUE" ]; then
                ((CORRECT_RESPONSES++))
                if [ $((i % 20)) -eq 0 ]; then
                    echo "   ✅ Key $KEY: Correct (${ACTUAL_VALUE:0:20}...)"
                fi
            else
                echo "   ❌ Key $KEY: Wrong value"
                echo "      Expected: $EXPECTED_VALUE"
                echo "      Got:      $ACTUAL_VALUE"
                ((WRONG_RESPONSES++))
            fi
        else
            echo "   ❌ Key $KEY: Incomplete response"
            ((MISSING_RESPONSES++))
        fi
    else
        echo "   ❌ Key $KEY: Invalid response format: $RESP_LINE"
        ((WRONG_RESPONSES++))
        ((response_idx++))
    fi
    
    ((i++))
done

# Test 3: Cross-shard validation
echo ""
echo "🔄 TEST 3: Cross-shard distribution validation"
SHARD_DISTRIBUTION=()
for i in $(seq 0 3); do
    SHARD_DISTRIBUTION[$i]=0
done

for i in $(seq 0 $((NUM_KEYS-1))); do
    KEY="${KEYS[$i]}"
    # Simple hash simulation (not exact, but gives us distribution idea)
    HASH=$(echo -n "$KEY" | cksum | cut -d' ' -f1)
    SHARD=$((HASH % 4))
    ((SHARD_DISTRIBUTION[$SHARD]++))
done

echo "   Key distribution across shards:"
for i in $(seq 0 3); do
    echo "   Shard $i: ${SHARD_DISTRIBUTION[$i]} keys"
done

# Final Results
echo ""
echo "📊 FINAL RESULTS:"
echo "   ✅ Correct responses: $CORRECT_RESPONSES"
echo "   ❌ Wrong responses:   $WRONG_RESPONSES" 
echo "   🔍 Missing responses: $MISSING_RESPONSES"
echo "   📈 Success rate:      $((CORRECT_RESPONSES * 100 / NUM_KEYS))%"
echo ""

if [ "$CORRECT_RESPONSES" -eq "$NUM_KEYS" ]; then
    echo "🎉 SUCCESS: Pipeline correctness test PASSED!"
    echo "   All $NUM_KEYS keys correctly SET and GET in pipeline mode"
    echo "   Cross-shard operations working properly"
    exit 0
elif [ "$CORRECT_RESPONSES" -gt $((NUM_KEYS * 80 / 100)) ]; then
    echo "⚠️  WARNING: Pipeline correctness test MOSTLY PASSED"
    echo "   $CORRECT_RESPONSES/$NUM_KEYS responses correct (>80%)"
    echo "   Some cross-shard operations may have issues"
    exit 1
else
    echo "❌ FAILURE: Pipeline correctness test FAILED"
    echo "   Only $CORRECT_RESPONSES/$NUM_KEYS responses correct (<80%)"
    echo "   Pipeline cross-shard routing is broken"
    exit 2
fi













