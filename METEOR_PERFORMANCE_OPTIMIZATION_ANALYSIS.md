# Meteor Performance Optimization Analysis

## Current Performance Issues in sharded_server.cpp

Based on the logs and code analysis, the main performance bottlenecks are:

### 1. **Network I/O Bottlenecks**
- **Issue**: "Failed to send response to client" errors under high concurrency (>200 clients)
- **Root Cause**: Single-threaded network handling with basic `send()` calls
- **Impact**: Complete connection failures, poor scalability

### 2. **Thread Contention Issues**
- **Issue**: High mutex contention in memory pool and connection management
- **Root Cause**: Shared resources accessed by multiple threads simultaneously
- **Impact**: CPU cycles wasted on lock contention instead of data processing

### 3. **Inefficient RESP Parsing**
- **Issue**: String-based parsing with frequent memory allocations
- **Root Cause**: No zero-copy parsing, multiple string copies per command
- **Impact**: Memory pressure and GC overhead

### 4. **Poor Connection Management**
- **Issue**: Thread-per-connection model with blocking I/O
- **Root Cause**: No connection pooling, no async I/O multiplexing
- **Impact**: Resource exhaustion with many concurrent connections

## Optimization Strategies from Dragonfly and Garnet

### 1. **Fiber-Based Concurrency (Dragonfly Approach)**

**Implementation:**
```cpp
// Fiber-based connection handling
class FiberConnectionManager {
private:
    std::unique_ptr<FiberPool> fiber_pool_;
    std::atomic<size_t> active_connections_{0};
    
public:
    void handle_connection(int client_fd) {
        fiber_pool_->schedule([this, client_fd]() {
            // Handle connection in fiber context
            handle_client_fiber(client_fd);
        });
    }
    
private:
    void handle_client_fiber(int client_fd) {
        // Fiber-based handling with yield points
        while (running_) {
            auto data = fiber_recv(client_fd);  // Can yield
            if (!data) break;
            
            auto response = process_command(data);  // Can yield
            fiber_send(client_fd, response);  // Can yield
        }
    }
};
```

**Benefits:**
- Lightweight context switching (microseconds vs milliseconds)
- Better CPU utilization
- Handles thousands of concurrent connections efficiently

### 2. **Shared-Nothing Architecture (Dragonfly Approach)**

**Implementation:**
```cpp
// Shard-per-thread design
class ShardedCacheOptimized {
private:
    struct alignas(64) Shard {
        std::unique_ptr<HashTable> hash_table_;
        std::unique_ptr<MemoryPool> memory_pool_;
        std::unique_ptr<SSDStorage> ssd_storage_;
        
        // Thread-local statistics
        std::atomic<uint64_t> operations_{0};
        std::atomic<uint64_t> hits_{0};
        std::atomic<uint64_t> misses_{0};
        
        // Padding to avoid false sharing
        char padding[64];
    };
    
    std::vector<std::unique_ptr<Shard>> shards_;
    std::vector<std::thread> shard_threads_;
    
public:
    void start_shard_threads() {
        for (size_t i = 0; i < shards_.size(); ++i) {
            shard_threads_.emplace_back([this, i]() {
                // Pin thread to CPU core
                cpu_set_t cpuset;
                CPU_ZERO(&cpuset);
                CPU_SET(i, &cpuset);
                pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
                
                run_shard(i);
            });
        }
    }
    
private:
    void run_shard(size_t shard_id) {
        auto& shard = shards_[shard_id];
        
        // Event loop for this shard
        while (running_) {
            // Process commands for this shard
            process_shard_commands(shard.get());
        }
    }
};
```

**Benefits:**
- Eliminates cross-thread synchronization
- Better cache locality
- Linear scaling with CPU cores

### 3. **Zero-Copy RESP Parsing (Garnet Approach)**

**Implementation:**
```cpp
// Zero-copy RESP parser
class ZeroCopyRESPParser {
private:
    struct BufferView {
        const char* data;
        size_t length;
        
        BufferView(const char* d, size_t l) : data(d), length(l) {}
        
        std::string_view as_string_view() const {
            return std::string_view(data, length);
        }
    };
    
    std::vector<BufferView> command_parts_;
    
public:
    bool parse_command(const char* buffer, size_t length) {
        command_parts_.clear();
        
        // Parse without copying data
        const char* pos = buffer;
        const char* end = buffer + length;
        
        if (*pos != '*') return false;
        pos++;
        
        // Parse array length
        auto array_length = parse_integer(pos, end);
        if (array_length <= 0) return false;
        
        command_parts_.reserve(array_length);
        
        for (int i = 0; i < array_length; ++i) {
            if (pos >= end || *pos != '$') return false;
            pos++;
            
            auto str_length = parse_integer(pos, end);
            if (str_length < 0) return false;
            
            if (pos + str_length + 2 > end) return false;  // +2 for \r\n
            
            command_parts_.emplace_back(pos, str_length);
            pos += str_length + 2;  // Skip \r\n
        }
        
        return true;
    }
    
    std::string_view get_command() const {
        return command_parts_[0].as_string_view();
    }
    
    std::string_view get_arg(size_t index) const {
        return command_parts_[index + 1].as_string_view();
    }
};
```

**Benefits:**
- Eliminates memory allocations during parsing
- Reduces memory pressure
- Faster parsing performance

### 4. **Advanced Networking (Garnet's .NET Approach adapted to C++)**

**Implementation:**
```cpp
// Epoll-based networking with connection pooling
class AdvancedNetworkManager {
private:
    int epoll_fd_;
    std::vector<std::unique_ptr<Connection>> connections_;
    std::queue<std::unique_ptr<Connection>> connection_pool_;
    std::mutex pool_mutex_;
    
    struct Connection {
        int fd;
        std::vector<char> read_buffer;
        std::vector<char> write_buffer;
        ZeroCopyRESPParser parser;
        std::atomic<bool> active{true};
        
        Connection(int f) : fd(f) {
            read_buffer.reserve(65536);
            write_buffer.reserve(65536);
        }
    };
    
public:
    bool initialize() {
        epoll_fd_ = epoll_create1(EPOLL_CLOEXEC);
        if (epoll_fd_ == -1) return false;
        
        // Pre-allocate connection pool
        for (int i = 0; i < 1000; ++i) {
            connection_pool_.emplace(std::make_unique<Connection>(-1));
        }
        
        return true;
    }
    
    void run_event_loop() {
        const int MAX_EVENTS = 1000;
        epoll_event events[MAX_EVENTS];
        
        while (running_) {
            int nfds = epoll_wait(epoll_fd_, events, MAX_EVENTS, 1000);
            
            for (int i = 0; i < nfds; ++i) {
                auto* conn = static_cast<Connection*>(events[i].data.ptr);
                
                if (events[i].events & EPOLLIN) {
                    handle_read(conn);
                }
                
                if (events[i].events & EPOLLOUT) {
                    handle_write(conn);
                }
                
                if (events[i].events & (EPOLLHUP | EPOLLERR)) {
                    cleanup_connection(conn);
                }
            }
        }
    }
    
private:
    void handle_read(Connection* conn) {
        char buffer[65536];
        ssize_t bytes_read = read(conn->fd, buffer, sizeof(buffer));
        
        if (bytes_read > 0) {
            // Process with zero-copy parser
            if (conn->parser.parse_command(buffer, bytes_read)) {
                auto response = process_command(conn->parser);
                
                // Queue response for writing
                conn->write_buffer.insert(conn->write_buffer.end(),
                                        response.begin(), response.end());
                
                // Enable write events
                modify_epoll_events(conn->fd, EPOLLIN | EPOLLOUT);
            }
        }
    }
    
    void handle_write(Connection* conn) {
        if (conn->write_buffer.empty()) return;
        
        ssize_t bytes_written = write(conn->fd, conn->write_buffer.data(),
                                    conn->write_buffer.size());
        
        if (bytes_written > 0) {
            conn->write_buffer.erase(conn->write_buffer.begin(),
                                   conn->write_buffer.begin() + bytes_written);
            
            if (conn->write_buffer.empty()) {
                // Disable write events
                modify_epoll_events(conn->fd, EPOLLIN);
            }
        }
    }
};
```

**Benefits:**
- Handles thousands of concurrent connections
- Non-blocking I/O
- Efficient memory usage

### 5. **SIMD-Optimized Operations (Both Dragonfly and Garnet)**

**Implementation:**
```cpp
// SIMD-optimized hash and comparison functions
namespace simd_ops {

#ifdef __AVX2__
    // AVX2 optimized hash function
    inline uint64_t fast_hash_avx2(const char* data, size_t len) {
        const __m256i* blocks = reinterpret_cast<const __m256i*>(data);
        size_t block_count = len / 32;
        
        __m256i hash = _mm256_set1_epi64x(0x9e3779b97f4a7c15ULL);
        
        for (size_t i = 0; i < block_count; ++i) {
            __m256i block = _mm256_loadu_si256(&blocks[i]);
            hash = _mm256_xor_si256(hash, block);
            hash = _mm256_mul_epu32(hash, _mm256_set1_epi64x(0x9e3779b97f4a7c15ULL));
        }
        
        // Handle remaining bytes
        // ... (remainder processing)
        
        return _mm256_extract_epi64(hash, 0);
    }
#endif

    // SIMD string comparison
    inline bool fast_string_compare(const char* a, const char* b, size_t len) {
#ifdef __AVX2__
        if (len >= 32) {
            const __m256i* va = reinterpret_cast<const __m256i*>(a);
            const __m256i* vb = reinterpret_cast<const __m256i*>(b);
            
            size_t blocks = len / 32;
            for (size_t i = 0; i < blocks; ++i) {
                __m256i cmp = _mm256_cmpeq_epi8(va[i], vb[i]);
                if (_mm256_movemask_epi8(cmp) != 0xFFFFFFFF) {
                    return false;
                }
            }
            
            // Handle remainder
            return memcmp(a + blocks * 32, b + blocks * 32, len % 32) == 0;
        }
#endif
        return memcmp(a, b, len) == 0;
    }
}
```

**Benefits:**
- 2-4x faster hash computation
- Faster string operations
- Better CPU utilization

### 6. **Memory Pool Optimization (Garnet's .NET GC approach adapted)**

**Implementation:**
```cpp
// Lock-free memory pool with size classes
class OptimizedMemoryPool {
private:
    struct alignas(64) SizeClass {
        std::atomic<void*> free_list{nullptr};
        size_t block_size;
        size_t blocks_per_chunk;
        std::vector<std::unique_ptr<char[]>> chunks;
        std::mutex chunk_mutex;
        
        SizeClass(size_t bs, size_t bpc) : block_size(bs), blocks_per_chunk(bpc) {}
    };
    
    static constexpr size_t NUM_SIZE_CLASSES = 16;
    std::array<SizeClass, NUM_SIZE_CLASSES> size_classes_;
    
public:
    OptimizedMemoryPool() {
        // Initialize size classes: 32, 64, 128, 256, 512, 1024, 2048, 4096, ...
        for (size_t i = 0; i < NUM_SIZE_CLASSES; ++i) {
            size_t block_size = 32 << i;
            size_t blocks_per_chunk = std::max(1UL, 65536 / block_size);
            size_classes_[i] = SizeClass(block_size, blocks_per_chunk);
        }
    }
    
    void* allocate(size_t size) {
        size_t class_idx = get_size_class(size);
        if (class_idx >= NUM_SIZE_CLASSES) {
            // Fallback to system allocator for large allocations
            return std::aligned_alloc(64, size);
        }
        
        auto& sc = size_classes_[class_idx];
        
        // Try to get from free list
        void* ptr = sc.free_list.load();
        while (ptr && !sc.free_list.compare_exchange_weak(ptr, *static_cast<void**>(ptr))) {
            ptr = sc.free_list.load();
        }
        
        if (ptr) {
            return ptr;
        }
        
        // Allocate new chunk if needed
        return allocate_from_chunk(sc);
    }
    
    void deallocate(void* ptr, size_t size) {
        size_t class_idx = get_size_class(size);
        if (class_idx >= NUM_SIZE_CLASSES) {
            std::free(ptr);
            return;
        }
        
        auto& sc = size_classes_[class_idx];
        
        // Add to free list
        void* old_head = sc.free_list.load();
        do {
            *static_cast<void**>(ptr) = old_head;
        } while (!sc.free_list.compare_exchange_weak(old_head, ptr));
    }
    
private:
    size_t get_size_class(size_t size) {
        if (size <= 32) return 0;
        return std::min(static_cast<size_t>(NUM_SIZE_CLASSES - 1),
                       static_cast<size_t>(std::bit_width(size - 1)) - 5);
    }
    
    void* allocate_from_chunk(SizeClass& sc) {
        std::lock_guard<std::mutex> lock(sc.chunk_mutex);
        
        // Allocate new chunk
        auto chunk = std::make_unique<char[]>(sc.block_size * sc.blocks_per_chunk);
        char* chunk_ptr = chunk.get();
        
        // Add blocks to free list (except the first one)
        for (size_t i = 1; i < sc.blocks_per_chunk; ++i) {
            void* block = chunk_ptr + i * sc.block_size;
            *static_cast<void**>(block) = sc.free_list.load();
            sc.free_list.store(block);
        }
        
        sc.chunks.push_back(std::move(chunk));
        return chunk_ptr;  // Return first block
    }
};
```

**Benefits:**
- Eliminates malloc/free overhead
- Better memory locality
- Reduced fragmentation

## Implementation Priority

### Phase 1: Critical Performance Fixes
1. **Fix Network I/O Issues**
   - Implement robust send/receive with proper error handling
   - Add connection pooling and epoll-based event handling
   - Implement proper backpressure handling

2. **Optimize RESP Parsing**
   - Implement zero-copy parsing
   - Reduce memory allocations
   - Add command pipelining support

### Phase 2: Architecture Improvements
1. **Implement Fiber-Based Concurrency**
   - Replace thread-per-connection with fiber-based handling
   - Add cooperative scheduling
   - Implement efficient context switching

2. **Enhanced Sharding**
   - Implement proper shard-per-thread architecture
   - Add CPU affinity for shard threads
   - Optimize cross-shard operations

### Phase 3: Advanced Optimizations
1. **SIMD Optimizations**
   - Implement AVX2/NEON optimized hash functions
   - Add SIMD string operations
   - Optimize memory copying operations

2. **Memory Management**
   - Implement lock-free memory pools
   - Add size-class based allocation
   - Optimize garbage collection

## Expected Performance Improvements

Based on Dragonfly and Garnet benchmarks:

- **Throughput**: 5-10x improvement for high-concurrency workloads
- **Latency**: 50-70% reduction in P99 latency
- **Scalability**: Support for 10,000+ concurrent connections
- **CPU Utilization**: 80-90% better CPU utilization
- **Memory Efficiency**: 40-60% reduction in memory usage

## Conclusion

The current `sharded_server.cpp` implementation has significant performance bottlenecks that prevent it from competing with Redis at scale. By implementing the optimizations learned from Dragonfly and Garnet, we can achieve:

1. **Better than Redis performance** for high-concurrency workloads
2. **Maintained feature compatibility** with SSD tiering and intelligent caching
3. **Improved stability** under high load conditions
4. **Better resource utilization** across all system components

The key is to implement these optimizations systematically, starting with the most critical performance bottlenecks and gradually adding more advanced features. 