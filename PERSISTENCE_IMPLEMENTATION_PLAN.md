# Meteor Redis-Compatible Server: Data Persistence Implementation Plan

## Executive Summary

Implement production-grade data persistence for the Meteor Redis-compatible server with:
- **RDB (Redis Database) snapshots** at configurable intervals
- **AOF (Append-Only File)** for operations between snapshots
- **io_uring-based async I/O** for zero CPU impact during snapshots
- **Crash recovery** with data restored to correct shards
- **Zero performance regression** from current 5M+ QPS

## Architecture Overview

### 1. Persistence Components

```
┌─────────────────────────────────────────────────────────────┐
│                   Meteor Server (Main Process)              │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Core 0     │  │   Core 1     │  │   Core N     │     │
│  │  (Shard 0)   │  │  (Shard 1)   │  │  (Shard M)   │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│                            │                                 │
│         ┌──────────────────▼──────────────────┐             │
│         │    Persistence Coordinator          │             │
│         │  - RDB Snapshots (io_uring)         │             │
│         │  - AOF Writer (buffered)            │             │
│         │  - Recovery Manager                 │             │
│         └──────────────────┬──────────────────┘             │
└────────────────────────────┼──────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
       ┌────────▼────────┐       ┌───────▼────────┐
       │  RDB Files      │       │   AOF File     │
       │  (Snapshots)    │       │  (Operations)  │
       │  meteor_*.rdb   │       │  meteor.aof    │
       └─────────────────┘       └────────────────┘
```

### 2. RDB Snapshot Strategy

**Dragonfly-Inspired Design:**
- **Serialized per-shard** snapshots (avoids fork overhead)
- **io_uring async writes** (zero syscall overhead)
- **Streaming compression** using LZ4 for speed
- **Background fiber** for snapshot generation (non-blocking)

**File Format:**
```
+--------+----------+----------+----------+-----+
| Header | Shard 0  | Shard 1  | Shard N  | EOF |
+--------+----------+----------+----------+-----+

Header:
- Magic: "METEOR-RDB" (10 bytes)
- Version: uint16_t (2)
- Timestamp: uint64_t (8)
- Shard count: uint32_t (4)
- Compression: uint8_t (1) - 0=none, 1=LZ4, 2=ZSTD
- Checksum: uint64_t (8) - xxHash

Shard Data:
- Shard ID: uint32_t (4)
- Key count: uint32_t (4)
- Compressed size: uint64_t (8)
- Data: [key-length][key][value-length][value][ttl] ...
```

### 3. AOF Strategy

**Design:**
- **Append-only log** of write operations (SET, MSET, DEL, EXPIRE, etc.)
- **Buffered writes** with configurable fsync policy:
  - `always`: fsync after every command (safest, slowest)
  - `everysec`: fsync every second (balanced, recommended)
  - `no`: let OS handle (fastest, risk of data loss)
- **Automatic truncation** after successful RDB snapshot
- **RESP protocol format** for easy replay

**AOF Entry Format:**
```
*3\r\n$3\r\nSET\r\n$7\r\nmykey:0\r\n$8\r\nmyvalue\r\n
^
RESP array with command and arguments
```

### 4. Recovery Process

**Startup Sequence:**
```
1. Check for RDB snapshot (meteor_latest.rdb or latest timestamped)
2. Load RDB → distribute keys to correct shards via hash
3. Replay AOF → apply operations since last snapshot
4. Truncate AOF → start fresh append log
5. Start normal operations
```

**Shard Routing During Recovery:**
```cpp
// Ensure recovered keys go to correct shard
size_t target_shard = hash(key) % total_shards;
// Send key-value to target_shard for restoration
```

## Implementation Details

### 5. Key Code Changes

#### A. Add Persistence Configuration
```cpp
struct PersistenceConfig {
    bool enabled = true;
    std::string rdb_path = "./snapshots/";
    std::string aof_path = "./";
    std::string aof_filename = "meteor.aof";
    
    // RDB settings
    uint64_t snapshot_interval_seconds = 300;  // 5 minutes
    uint32_t snapshot_key_threshold = 100000;   // Or after 100K operations
    bool compress_snapshots = true;
    
    // AOF settings
    bool aof_enabled = true;
    uint32_t aof_fsync_policy = 2;  // 0=never, 1=always, 2=everysec
    bool aof_auto_truncate = true;
    
    // Recovery settings
    std::string recovery_mode = "auto";  // auto, rdb-only, aof-only
};
```

#### B. RDB Writer (io_uring based)
```cpp
class RDBSnapshotWriter {
private:
    io_uring ring_;
    PersistenceConfig config_;
    std::atomic<bool> snapshot_in_progress_{false};
    
public:
    // Non-blocking snapshot using Boost.Fiber
    boost::fibers::future<bool> create_snapshot_async(
        const std::vector<std::unordered_map<std::string, std::string>>& shard_data
    );
    
    // io_uring write submission
    void submit_write_batch(const std::vector<iovec>& buffers);
};
```

#### C. AOF Writer
```cpp
class AOFWriter {
private:
    std::ofstream aof_file_;
    std::mutex write_mutex_;
    std::thread fsync_thread_;
    std::deque<std::string> write_buffer_;
    
public:
    // Log command to AOF
    void log_command(const std::string& cmd, const std::vector<std::string>& args);
    
    // Truncate after snapshot
    void truncate_after_snapshot();
    
    // Background fsync
    void fsync_loop();  // Runs in background thread
};
```

#### D. Recovery Manager
```cpp
class RecoveryManager {
public:
    struct RecoveredData {
        std::unordered_map<std::string, std::string> data;
        size_t target_shard;  // Computed via hash(key) % total_shards
    };
    
    // Load RDB and AOF, return data grouped by shard
    std::vector<RecoveredData> recover_all_data(
        const std::string& rdb_path,
        const std::string& aof_path,
        size_t total_shards
    );
};
```

### 6. Integration Points

#### Point 1: Server Initialization
```cpp
// In main():
PersistenceConfig persistence_config = load_persistence_config(argc, argv);
RecoveryManager recovery;

if (persistence_config.enabled) {
    auto recovered_data = recovery.recover_all_data(
        persistence_config.rdb_path,
        persistence_config.aof_path,
        num_shards
    );
    
    // Distribute recovered data to correct shards
    for (const auto& shard_data : recovered_data) {
        send_recovery_data_to_shard(shard_data.target_shard, shard_data.data);
    }
}
```

#### Point 2: Command Logging
```cpp
// In DirectOperationProcessor::execute_single_operation():
ResponseInfo execute_single_operation(const SingleOperation& op) {
    // ... existing operation execution ...
    
    // Log write commands to AOF
    if (persistence_config_.aof_enabled && is_write_command(op.command)) {
        aof_writer_->log_command(op.command, {op.key, op.value});
    }
    
    return response;
}
```

#### Point 3: Snapshot Trigger
```cpp
// In CoreThread::run():
void run() {
    auto last_snapshot_time = std::chrono::steady_clock::now();
    uint64_t ops_since_snapshot = 0;
    
    while (running_) {
        // ... existing event loop ...
        
        // Check snapshot conditions
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
            now - last_snapshot_time
        ).count();
        
        if (persistence_config_.enabled &&
            (elapsed >= persistence_config_.snapshot_interval_seconds ||
             ops_since_snapshot >= persistence_config_.snapshot_key_threshold)) {
            
            // Trigger snapshot in background fiber
            boost::fibers::fiber([this]() {
                create_snapshot_background();
            }).detach();
            
            last_snapshot_time = now;
            ops_since_snapshot = 0;
        }
    }
}
```

## Performance Considerations

### 7. Zero-Impact Snapshot Design

**Problem:** Traditional fork() doubles memory usage and blocks on COW.

**Solution (Dragonfly-inspired):**
1. **Serialize each shard independently** using Boost.Fiber (non-blocking)
2. **Stream to io_uring** for async kernel writes (zero syscalls)
3. **LZ4 compression** in separate fiber (fast compression, \~500MB/s)
4. **No fork** → no memory doubling, no COW overhead

**Expected Impact:**
- Snapshot generation: 0.1-0.5% CPU overhead (background fiber)
- I/O: Fully async via io_uring (zero blocking)
- Memory: +10-20MB for compression buffers (negligible)

### 8. AOF Performance

**Buffered Write Strategy:**
```
┌──────────────┐
│  SET cmd     │──┐
│  GET cmd     │  │ (not logged)
│  MSET cmd    │──┤
│  DEL cmd     │──┤ Buffered
└──────────────┘  │
                  ▼
         ┌────────────────┐
         │  Write Buffer  │ (in-memory, fast)
         │  (deque)       │
         └────────┬───────┘
                  │ fsync every 1s
                  ▼
         ┌────────────────┐
         │   AOF File     │
         │ (meteor.aof)   │
         └────────────────┘
```

**Overhead:**
- In-memory append: \~50ns per command
- fsync (everysec): 1-5ms every second (background thread)
- Total impact: <0.1% QPS reduction

## Testing Strategy

### 9. Test Cases

1. **Basic Persistence:**
   ```bash
   # SET data → shutdown server → restart → GET data
   redis-cli SET key1 value1
   redis-cli SET key2 value2
   systemctl restart meteor
   redis-cli GET key1  # Should return value1
   ```

2. **Cross-Shard Recovery:**
   ```bash
   # SET 1000 keys → ensure they distribute correctly on restart
   for i in {1..1000}; do redis-cli SET key:$i value:$i; done
   systemctl restart meteor
   # Verify all 1000 keys exist and are in correct shards
   ```

3. **AOF Replay:**
   ```bash
   # Force snapshot → write more data → crash → recover
   redis-cli BGSAVE
   redis-cli SET newkey newvalue
   kill -9 <meteor-pid>
   systemctl start meteor
   redis-cli GET newkey  # Should return newvalue (from AOF)
   ```

4. **Performance Regression:**
   ```bash
   # Baseline: 5M+ QPS without persistence
   # Target: 4.95M+ QPS with persistence (< 1% regression)
   memtier_benchmark --threads=8 --clients=50 --requests=100000
   ```

## Implementation Phases

### Phase 1: RDB Snapshot (Week 1)
- [ ] Create `RDBSnapshotWriter` class with io_uring
- [ ] Implement per-shard serialization
- [ ] Add snapshot triggers (time & operation count)
- [ ] Test RDB generation and loading

### Phase 2: AOF Logging (Week 2)
- [ ] Create `AOFWriter` class with buffered writes
- [ ] Integrate command logging for write operations
- [ ] Implement AOF truncation after snapshot
- [ ] Test AOF replay

### Phase 3: Recovery (Week 3)
- [ ] Create `RecoveryManager` class
- [ ] Implement RDB loading with shard routing
- [ ] Implement AOF replay with shard routing
- [ ] Test full recovery flow

### Phase 4: Testing & Optimization (Week 4)
- [ ] Performance benchmarks (ensure <1% regression)
- [ ] Stress testing (1B keys, multiple restarts)
- [ ] Production validation on VMs
- [ ] Documentation

## Configuration Parameters

### 10. Command-Line Arguments

```bash
./meteor_server \
  --persist=true \
  --rdb-path=/var/lib/meteor/snapshots/ \
  --aof-path=/var/lib/meteor/ \
  --snapshot-interval=300 \
  --snapshot-threshold=100000 \
  --aof-fsync=everysec \
  --compress=lz4
```

## Monitoring & Observability

### 11. Metrics to Track

- `meteor_rdb_snapshots_total`: Count of successful snapshots
- `meteor_rdb_snapshot_duration_seconds`: Time taken for last snapshot
- `meteor_aof_writes_total`: Count of AOF write operations
- `meteor_aof_file_size_bytes`: Current AOF file size
- `meteor_recovery_keys_loaded`: Keys loaded during last recovery
- `meteor_persistence_errors_total`: Count of persistence errors

## References

- **Dragonfly persistence**: https://github.com/dragonflydb/dragonfly/tree/main/src/server
- **Redis RDB format**: https://github.com/redis/redis/blob/unstable/src/rdb.c
- **Redis AOF**: https://github.com/redis/redis/blob/unstable/src/aof.c
- **io_uring**: https://kernel.dk/io_uring.pdf
- **Existing implementation**: `cpp/meteor_v8_persistent_snapshot.cpp`

## Success Criteria

✅ RDB snapshots generated without blocking operations  
✅ AOF logs all write operations correctly  
✅ Recovery restores all data to correct shards  
✅ Performance: <1% regression (4.95M+ QPS maintained)  
✅ Memory: <5% increase during snapshot  
✅ Production-ready: Tested with 1B keys, 100+ restarts  
✅ Zero data loss: All data recovered after crash  

---

**Status**: Ready for Implementation  
**Estimated Effort**: 4 weeks (1 engineer)  
**Risk Level**: Medium (well-understood problem, proven solutions available)  



