# CPU Core Utilization Analysis - Meteor vs Dragonfly

## Current Meteor Architecture Issues

### 1. Single Event Loop Bottleneck
```cpp
// PROBLEM: Single thread handles ALL network events
void event_loop_thread() {
    while (running_.load()) {
        int num_events = event_loop_->wait_events(100);
        for (int i = 0; i < num_events; ++i) {
            // ALL requests processed sequentially by ONE thread
            handle_read(fd);  // This becomes the bottleneck
        }
    }
}
```

### 2. Incorrect Shard-to-Thread Mapping
```cpp
// PROBLEM: Shards exist but aren't bound to threads
size_t get_shard_index(const std::string& key) const {
    return hash::fast_hash(key) & shard_mask_;  // Hash-based routing
}

// But processing still goes through single event loop!
```

### 3. Shared Resource Contention
- All threads compete for the same event loop
- Cache shards are accessed from multiple threads
- No thread affinity or CPU pinning

## Dragonfly's Superior Design

### 1. Thread-per-Core Architecture
```cpp
// Each core gets its own complete processing unit
class ShardedThread {
    int cpu_id;                    // Pinned to specific CPU
    EventLoop event_loop;         // Dedicated event loop
    HashTable local_data;         // Owned data partition
    NetworkHandler network;       // Dedicated network handling
};
```

### 2. Partition-Based Key Routing
```cpp
// Keys are routed to specific threads at connection level
size_t target_thread = hash(key) % num_cores;
threads[target_thread].handle_request(request);
```

### 3. Zero Cross-Thread Communication
- Each thread owns its data completely
- No locks or atomic operations between threads
- Perfect CPU cache locality

## Performance Impact

### Current Meteor Issues:
- 1-2 cores at 100% (event loop bottleneck)
- Other cores idle or underutilized
- Poor cache locality
- High context switching overhead

### Dragonfly Benefits:
- All cores utilized equally
- Zero cross-thread contention
- Optimal cache locality
- Linear scalability with core count

## Solution Required

Implement true shared-nothing architecture:
1. One event loop per CPU core
2. Partition connections by hash at accept time
3. Bind each thread to specific CPU core
4. Eliminate cross-thread communication
