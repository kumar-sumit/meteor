# 🧪 **METEOR PERSISTENCE - TESTING GUIDE**

## **Overview**
This document provides comprehensive testing procedures for the Meteor Redis-compatible server with RDB + AOF persistence.

---

## **🚀 Quick Start**

### **1. Build the Server**

```bash
cd ~/Documents/personal/repo/meteor
./build_persistence_server.sh
```

### **2. Start Server with Persistence**

```bash
# Basic with default settings (5min snapshots, 100K operation threshold)
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1

# Custom settings
./meteor_redis_persistent -p 6379 -c 4 -s 4 \
  -P 1 \
  -R ./snapshots \
  -A ./ \
  -I 60 \
  -O 50000 \
  -F 2
```

**Options:**
- `-P 1`: Enable persistence
- `-R <path>`: RDB snapshot directory (default: `./snapshots`)
- `-A <path>`: AOF file directory (default: `./`)
- `-I <seconds>`: Snapshot interval (default: 300)
- `-O <count>`: Snapshot after N operations (default: 100000)
- `-F <0|1|2>`: AOF fsync policy (0=never, 1=always, 2=everysec, default: 2)

---

## **✅ Test Suite**

### **Test 1: Basic Persistence - Data Survives Restart**

#### **Objective:** Verify that SET/GET data is persisted and recovered after server restart.

```bash
# Step 1: Start server with persistence
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 &
SERVER_PID=$!
sleep 3

# Step 2: Insert test data
redis-cli -p 6379 SET key1 "value1"
redis-cli -p 6379 SET key2 "value2"
redis-cli -p 6379 MSET key3 "value3" key4 "value4"
redis-cli -p 6379 SETEX key5 3600 "value5_with_ttl"

# Step 3: Wait for snapshot (or trigger manually by waiting for interval)
echo "⏳ Waiting for snapshot... (60s)"
sleep 65

# Step 4: Verify files created
ls -lh snapshots/
ls -lh meteor.aof

# Step 5: Restart server (kill and start again)
kill -9 $SERVER_PID
sleep 2
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 &
SERVER_PID=$!
sleep 3

# Step 6: Verify data
echo "🔍 Verifying recovered data..."
redis-cli -p 6379 GET key1  # Should return "value1"
redis-cli -p 6379 GET key2  # Should return "value2"
redis-cli -p 6379 GET key3  # Should return "value3"
redis-cli -p 6379 GET key4  # Should return "value4"
redis-cli -p 6379 GET key5  # Should return "value5_with_ttl"

# Cleanup
kill $SERVER_PID
```

**Expected Result:** All keys return their correct values after server restart.

---

### **Test 2: AOF Replay - Operations After Snapshot**

#### **Objective:** Verify that AOF replays operations that occurred after the last RDB snapshot.

```bash
# Step 1: Start server
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 300 &
SERVER_PID=$!
sleep 3

# Step 2: Insert initial data and wait for snapshot
redis-cli -p 6379 SET initial_key "initial_value"
sleep 305  # Wait for first snapshot

# Step 3: Insert more data (after snapshot)
redis-cli -p 6379 SET after_snapshot_key1 "after_value1"
redis-cli -p 6379 SET after_snapshot_key2 "after_value2"
redis-cli -p 6379 DEL initial_key

# Step 4: Verify AOF file has new operations
cat meteor.aof | grep "after_snapshot"

# Step 5: Restart server (without waiting for another snapshot)
kill -9 $SERVER_PID
sleep 2
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 300 &
SERVER_PID=$!
sleep 3

# Step 6: Verify data
redis-cli -p 6379 GET after_snapshot_key1  # Should return "after_value1"
redis-cli -p 6379 GET after_snapshot_key2  # Should return "after_value2"
redis-cli -p 6379 GET initial_key  # Should return (nil) because it was deleted

# Cleanup
kill $SERVER_PID
```

**Expected Result:** All operations after the snapshot are replayed from AOF.

---

### **Test 3: Crash Recovery - Simulated Power Loss**

#### **Objective:** Verify data integrity after abrupt termination (kill -9).

```bash
# Step 1: Start server
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 &
SERVER_PID=$!
sleep 3

# Step 2: Insert critical data
for i in {1..1000}; do
    redis-cli -p 6379 SET crash_test_key_$i "crash_test_value_$i" > /dev/null
done

# Step 3: Wait for snapshot
sleep 65

# Step 4: Insert more data
for i in {1001..2000}; do
    redis-cli -p 6379 SET crash_test_key_$i "crash_test_value_$i" > /dev/null
done

# Step 5: Simulate crash (kill -9)
echo "💥 Simulating crash..."
kill -9 $SERVER_PID
sleep 2

# Step 6: Restart and verify
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 &
SERVER_PID=$!
sleep 3

# Step 7: Verify all data
echo "🔍 Verifying crash recovery..."
MISSING_KEYS=0
for i in {1..2000}; do
    VALUE=$(redis-cli -p 6379 GET crash_test_key_$i 2>/dev/null)
    if [ "$VALUE" != "crash_test_value_$i" ]; then
        ((MISSING_KEYS++))
    fi
done

echo "Missing keys: $MISSING_KEYS / 2000"

# Cleanup
kill $SERVER_PID
```

**Expected Result:** All 2000 keys recovered correctly (MISSING_KEYS = 0).

---

### **Test 4: Performance Regression - Throughput Comparison**

#### **Objective:** Verify persistence adds <1% overhead.

```bash
# Baseline without persistence
./meteor_redis_client_compatible -p 6379 -c 4 -s 4 &
BASELINE_PID=$!
sleep 3

echo "📊 Running baseline benchmark..."
memtier_benchmark \
  --server 127.0.0.1 \
  --port 6379 \
  --clients 50 \
  --threads 4 \
  --pipeline 10 \
  --data-size 100 \
  --requests 100000 \
  --key-pattern R:R \
  --ratio 1:3 \
  > baseline_results.txt

BASELINE_OPS=$(grep "Ops/sec" baseline_results.txt | awk '{print $2}')
echo "Baseline: $BASELINE_OPS ops/sec"

kill $BASELINE_PID
sleep 2

# With persistence
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 300 -F 2 &
PERSIST_PID=$!
sleep 3

echo "📊 Running persistence benchmark..."
memtier_benchmark \
  --server 127.0.0.1 \
  --port 6379 \
  --clients 50 \
  --threads 4 \
  --pipeline 10 \
  --data-size 100 \
  --requests 100000 \
  --key-pattern R:R \
  --ratio 1:3 \
  > persistence_results.txt

PERSIST_OPS=$(grep "Ops/sec" persistence_results.txt | awk '{print $2}')
echo "With Persistence: $PERSIST_OPS ops/sec"

# Calculate regression
REGRESSION=$(echo "scale=2; ($BASELINE_OPS - $PERSIST_OPS) / $BASELINE_OPS * 100" | bc)
echo "Regression: $REGRESSION%"

kill $PERSIST_PID
```

**Expected Result:** Regression < 1% (typically 0.5-0.8%).

---

### **Test 5: Shard Affinity - Keys Restored to Correct Shards**

#### **Objective:** Verify that keys are restored to the same shard they were stored in.

```bash
# Step 1: Start server with persistence
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 &
SERVER_PID=$!
sleep 3

# Step 2: Insert keys that should go to different shards
# We'll hash keys to ensure they go to different shards
redis-cli -p 6379 SET shard0_key1 "value_shard0_1"
redis-cli -p 6379 SET shard1_key1 "value_shard1_1"
redis-cli -p 6379 SET shard2_key1 "value_shard2_1"
redis-cli -p 6379 SET shard3_key1 "value_shard3_1"

# Step 3: Wait for snapshot
sleep 65

# Step 4: Restart server
kill -9 $SERVER_PID
sleep 2
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 &
SERVER_PID=$!
sleep 3

# Step 5: Verify all keys (shard routing should be correct)
redis-cli -p 6379 GET shard0_key1  # Should return "value_shard0_1"
redis-cli -p 6379 GET shard1_key1  # Should return "value_shard1_1"
redis-cli -p 6379 GET shard2_key1  # Should return "value_shard2_1"
redis-cli -p 6379 GET shard3_key1  # Should return "value_shard3_1"

# Cleanup
kill $SERVER_PID
```

**Expected Result:** All keys return correct values, indicating proper shard routing.

---

### **Test 6: High Load Stability - 1M Operations**

#### **Objective:** Verify persistence remains stable under heavy load.

```bash
# Start server with persistence
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 -F 2 &
SERVER_PID=$!
sleep 3

# Run high-load test
echo "🚀 Running high-load test (1M operations)..."
memtier_benchmark \
  --server 127.0.0.1 \
  --port 6379 \
  --clients 100 \
  --threads 8 \
  --pipeline 20 \
  --data-size 100 \
  --requests 125000 \
  --key-pattern R:R \
  --ratio 1:3 \
  --test-time 300

# Check server is still responsive
redis-cli -p 6379 PING

# Check for any errors in server logs
echo "✅ Test complete - checking server health..."

# Cleanup
kill $SERVER_PID
```

**Expected Result:** Server remains stable, no crashes, PING returns PONG.

---

### **Test 7: AOF Truncation - Verify AOF Clears After Snapshot**

#### **Objective:** Verify AOF file is truncated after successful RDB snapshot.

```bash
# Step 1: Start server
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -I 60 &
SERVER_PID=$!
sleep 3

# Step 2: Insert data
for i in {1..1000}; do
    redis-cli -p 6379 SET truncate_test_key_$i "truncate_value_$i" > /dev/null
done

# Step 3: Check AOF size before snapshot
AOF_SIZE_BEFORE=$(stat -f%z meteor.aof 2>/dev/null || stat -c%s meteor.aof)
echo "AOF size before snapshot: $AOF_SIZE_BEFORE bytes"

# Step 4: Wait for snapshot
sleep 65

# Step 5: Check AOF size after snapshot
AOF_SIZE_AFTER=$(stat -f%z meteor.aof 2>/dev/null || stat -c%s meteor.aof)
echo "AOF size after snapshot: $AOF_SIZE_AFTER bytes"

# Verify truncation
if [ $AOF_SIZE_AFTER -lt $AOF_SIZE_BEFORE ]; then
    echo "✅ AOF truncated successfully"
else
    echo "❌ AOF not truncated"
fi

# Cleanup
kill $SERVER_PID
```

**Expected Result:** AOF file size decreases significantly after snapshot.

---

## **📊 Performance Benchmarks**

### **Expected Metrics**

| Metric | Without Persistence | With Persistence | Impact |
|--------|---------------------|------------------|--------|
| **Throughput** | 5.0M+ ops/sec | 4.95M+ ops/sec | <1% |
| **P50 Latency** | 0.10ms | 0.10ms | +0.00ms |
| **P99 Latency** | 0.26ms | 0.27ms | +0.01ms |
| **P99.9 Latency** | 0.50ms | 0.52ms | +0.02ms |
| **CPU (snapshot)** | 0% | 0.1-0.5% | Minimal |
| **Memory** | Baseline | +10-20MB | Buffers |
| **Disk I/O** | 0 MB/s | 5-10 MB/s | AOF writes |

---

## **🔍 Troubleshooting**

### **Issue: Server won't start**

**Check:**
```bash
# Verify persistence directories exist and are writable
mkdir -p ./snapshots
chmod 777 ./snapshots

# Check for permission errors
ls -la snapshots/
ls -la meteor.aof
```

### **Issue: Data not recovered after restart**

**Debug:**
```bash
# Check if RDB snapshot exists
ls -lh snapshots/

# Check if AOF file exists and has content
cat meteor.aof

# Enable verbose logging
./meteor_redis_persistent -p 6379 -c 4 -s 4 -P 1 -l
```

### **Issue: Performance degradation**

**Solutions:**
1. Increase snapshot interval: `-I 600` (10 minutes)
2. Increase operation threshold: `-O 200000` (200K operations)
3. Change AOF fsync policy: `-F 0` (never) or `-F 2` (everysec)
4. Disable compression: (requires code change, set `compress_snapshots = false`)

---

## **🎯 Production Deployment Checklist**

- [ ] Persistence enabled with appropriate intervals
- [ ] RDB snapshot directory has sufficient disk space (estimate: 1GB per 10M keys)
- [ ] AOF fsync policy set to `everysec` (balance of durability and performance)
- [ ] Tested recovery after crash/restart
- [ ] Performance regression verified < 1%
- [ ] Monitoring for snapshot failures (check logs)
- [ ] Backup strategy for RDB/AOF files (e.g., rsync to remote storage)
- [ ] Tested with production-like workload

---

## **📝 Next Steps**

1. ✅ Complete Test Suite (all 7 tests)
2. ✅ Verify performance metrics match expectations
3. ✅ Deploy to `mcache-lssd-sumit` VM for integration testing
4. ✅ Run 24-hour stability test
5. ✅ Document any issues and create production runbook

---

**Questions or Issues?**
- Check `PERSISTENCE_IMPLEMENTATION_GUIDE.md` for architectural details
- Review server logs for error messages
- Verify all dependencies are installed (`./build_persistence_server.sh`)



