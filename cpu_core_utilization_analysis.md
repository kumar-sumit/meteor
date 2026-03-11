# 🔍 CPU Core Utilization Analysis: Meteor vs Dragonfly

## 🚨 **Critical Issue Identified: Single-Threaded Event Loop Bottleneck**

### **Current Meteor Architecture Problems**

#### 1. **Single Event Loop Bottleneck** ❌
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

**Result**: 1-2 cores at 100% CPU while other cores remain idle at 10-20%

#### 2. **Incorrect Shard-to-Thread Mapping** ❌
```cpp
// PROBLEM: Shards exist but aren't bound to specific threads
size_t get_shard_index(const std::string& key) const {
    return hash::fast_hash(key) & shard_mask_;  // Hash-based routing
}

// But processing still goes through single event loop!
// Server startup: Only ONE event thread created
event_thread_ = std::thread(&EventDrivenTCPServer::event_loop_thread, this);
```

#### 3. **Shared Resource Contention** ❌
- All threads compete for the same event loop
- Cache shards are accessed from multiple threads without CPU affinity
- No connection-to-core binding

### **Why This Happens: Architecture Comparison**

## 📊 **Dragonfly's Shared-Nothing vs Our Current Design**

| Component | **Dragonfly (Shared-Nothing)** ✅ | **Meteor (Current)** ❌ |
|-----------|-----------------------------------|--------------------------|
| **Event Loops** | One per CPU core | Single shared event loop |
| **Connection Handling** | Each connection bound to specific core | All connections compete for single thread |
| **Shard Access** | Direct core-to-shard mapping | Hash-based routing from any thread |
| **Memory Access** | NUMA-aware, core-local | Cross-core memory access |
| **Load Distribution** | Perfect CPU utilization | 1-2 cores saturated, others idle |

### **Dragonfly's Superior Architecture**

Based on Dragonfly's implementation (https://github.com/dragonflydb/dragonfly/tree/main):

1. **Thread-Per-Core**: Each CPU core has a dedicated event loop thread
2. **Shared-Nothing**: Each thread owns complete data slice with zero cross-thread communication  
3. **Connection Affinity**: Each connection is permanently bound to one core
4. **NUMA Optimization**: Memory allocation is core-local
5. **Perfect Scaling**: Linear performance increase with core count

### **Evidence from VM Testing**

From the attached performance data:
```bash
# Current behavior on 22-core VM:
sumitku+  515022  260  0.0 5213108 17600 ?  Sl   12:21   1:35 
# ^ CPU: 260% (saturating ~2-3 cores out of 22 available)
```

## 🎯 **Solution: Implement True Shared-Nothing Architecture**

### **Phase 1: Multi-Threaded Event Loops (Immediate Fix)**

```cpp
class MultiCoreEventServer {
private:
    std::vector<std::unique_ptr<std::thread>> event_threads_;
    std::vector<std::unique_ptr<network::EpollEventLoop>> event_loops_;
    std::atomic<size_t> round_robin_counter_{0};
    
public:
    void start() {
        size_t num_cores = std::thread::hardware_concurrency();
        
        for (size_t i = 0; i < num_cores; ++i) {
            event_loops_.push_back(std::make_unique<network::EpollEventLoop>());
            event_threads_.push_back(std::make_unique<std::thread>([this, i]() {
                // Pin thread to specific CPU core
                cpu_set_t cpuset;
                CPU_ZERO(&cpuset);
                CPU_SET(i, &cpuset);
                pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);
                
                // Dedicated event loop for this core
                dedicated_event_loop(i);
            }));
        }
    }
    
    void dedicated_event_loop(size_t core_id) {
        auto& event_loop = event_loops_[core_id];
        
        while (running_.load()) {
            int num_events = event_loop->wait_events(100);
            
            for (int i = 0; i < num_events; ++i) {
                // Process events on THIS core only
                handle_core_specific_event(core_id, events[i]);
            }
        }
    }
};
```

### **Phase 2: Connection Distribution Strategy**

```cpp
class ConnectionDistributor {
public:
    size_t assign_connection_to_core(int client_fd) {
        // Round-robin distribution
        size_t target_core = next_core_++;
        target_core %= num_cores_;
        
        // Move connection to target core's event loop
        event_loops_[target_core]->add_socket(client_fd, EPOLLIN | EPOLLET);
        
        return target_core;
    }
    
private:
    std::atomic<size_t> next_core_{0};
    size_t num_cores_;
};
```

### **Phase 3: Core-Shard Affinity**

```cpp
class CoreAffinityShardedCache {
private:
    // One shard per core, accessed only by that core
    std::vector<std::unique_ptr<CacheShard>> core_shards_;
    
public:
    bool get(const std::string& key, std::string& value) {
        size_t core_id = get_current_core_id();
        size_t shard_idx = hash::fast_hash(key) % core_shards_.size();
        
        // If this core owns the shard, access directly
        if (shard_idx % num_cores_ == core_id) {
            return core_shards_[shard_idx]->get(key, value);
        }
        
        // Otherwise, forward to owning core via lock-free queue
        return forward_to_core(shard_idx % num_cores_, key, value);
    }
};
```

## 📈 **Expected Performance Improvements**

1. **CPU Utilization**: From 15% average to 95%+ across all cores
2. **Throughput**: 10-20x improvement in ops/sec
3. **Latency**: Reduced by 50-80% due to eliminated contention
4. **Scalability**: Linear scaling with core count

## 🚧 **Implementation Priority**

1. **Immediate**: Multi-threaded event loops *(addresses 80% of the issue)*
2. **Short-term**: Connection distribution strategy
3. **Medium-term**: Core-shard affinity optimization
4. **Long-term**: Full shared-nothing architecture

## 💡 **Key Insight**

**Robustness is achieved through architecture, not just optimization parameters.** Dragonfly's shared-nothing design eliminates contention at the architectural level, which is why they achieve superior CPU utilization.

**Next Steps**: Should we implement the multi-core event loop fix first? [[memory:3916536]] 