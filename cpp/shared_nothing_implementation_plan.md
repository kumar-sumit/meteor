# Shared-Nothing Architecture Implementation Plan

## Phase 1: Multi-Threaded Event Loops (Immediate Fix)

### Problem: Single event loop thread bottleneck
### Solution: One event loop per CPU core

```cpp
class MultiThreadedEventServer {
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
                pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
                
                // Dedicated event loop for this core
                event_loops_[i]->run();
            }));
        }
    }
    
    void distribute_connection(int client_fd) {
        // Round-robin distribution to event loops
        size_t target_thread = round_robin_counter_.fetch_add(1) % event_threads_.size();
        event_loops_[target_thread]->add_socket(client_fd, EPOLLIN | EPOLLET);
    }
};
```

## Phase 2: Connection-Level Partitioning

### Problem: Connections not properly distributed
### Solution: Hash-based connection assignment

```cpp
class ConnectionPartitioner {
private:
    std::vector<std::unique_ptr<ConnectionHandler>> handlers_;
    
public:
    void assign_connection(int client_fd, const std::string& client_ip) {
        // Hash client connection to specific handler thread
        size_t handler_id = std::hash<std::string>{}(client_ip) % handlers_.size();
        handlers_[handler_id]->add_connection(client_fd);
    }
};
```

## Phase 3: True Shared-Nothing Data Partitioning

### Problem: Shards accessed from multiple threads
### Solution: Thread-owned data partitions

```cpp
class SharedNothingCore {
private:
    int core_id_;
    std::unique_ptr<network::EpollEventLoop> event_loop_;
    std::unique_ptr<CacheShard> owned_shard_;  // OWNED by this thread only
    std::unordered_map<int, ConnectionState> connections_;
    
public:
    void run() {
        // Pin to CPU core
        pin_to_cpu(core_id_);
        
        while (running_) {
            // Handle events for THIS core only
            auto events = event_loop_->wait_events();
            for (auto& event : events) {
                handle_local_event(event);  // No cross-thread calls
            }
        }
    }
    
    void handle_request(const std::string& key, const Command& cmd) {
        // All data is local - no locks needed
        owned_shard_->execute(key, cmd);
    }
};
```

## Phase 4: Key-Based Request Routing

### Problem: Requests not routed to correct thread
### Solution: Route at connection establishment

```cpp
class KeyBasedRouter {
public:
    size_t get_target_core(const std::string& key) {
        return hash::consistent_hash(key) % num_cores_;
    }
    
    void route_request(const std::string& key, const Command& cmd) {
        size_t target_core = get_target_core(key);
        cores_[target_core]->enqueue_request(key, cmd);
    }
};
```

## Implementation Priority

1. **IMMEDIATE**: Multi-threaded event loops (fixes 80% of CPU utilization)
2. **SHORT-TERM**: Connection partitioning (improves load distribution)
3. **MEDIUM-TERM**: Shared-nothing data ownership (eliminates contention)
4. **LONG-TERM**: Advanced routing and optimization

## Expected Performance Improvement

- **Current**: 1-2 cores at 100%, others idle
- **After Fix**: All cores at 80-90% utilization
- **Throughput**: 4-8x improvement depending on core count
- **Latency**: 50-70% reduction due to better cache locality
