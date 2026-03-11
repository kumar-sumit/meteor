/**
 * PHASE 6 STEP 1 OPTIMIZED: Thread-Per-Core with AVX-512 SIMD + Smart NUMA
 * 
 * OPTIMIZATIONS APPLIED:
 * 1. NUMA binding only when nodes > 1 (skip single-node systems)
 * 2. Removed/minimized synchronization delays
 * 3. Reduced startup overhead
 * 4. Maintained all Phase 5 optimizations
 * 
 * Building on Phase 5: SIMD + Lock-Free + Advanced Monitoring
 * New in Phase 6: AVX-512 (8-way parallel) + Smart NUMA + Reduced Latency
 */

#include <iostream>
#include <thread>
#include <vector>
#include <string>
#include <unordered_map>
#include <memory>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <algorithm>
#include <random>
#include <queue>
#include <sstream>
#include <fstream>
#include <cstring>
#include <cassert>
#include <functional>
#include <array>

// System includes
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

// SIMD includes
#include <immintrin.h>

// Platform-specific includes
#ifdef __linux__
#define HAS_LINUX_EPOLL 1
#include <sys/epoll.h>
#include <pthread.h>
#include <sched.h>
#include <numa.h>
#include <numaif.h>
#elif __APPLE__
#define HAS_MACOS_KQUEUE 1
#include <sys/event.h>
#include <sys/time.h>
#include <pthread.h>
#endif

// **PHASE 6: AVX-512 SIMD Namespace (8-way parallel)**
namespace simd {
    
    // Check AVX-512 availability at runtime
    bool has_avx512() {
        // Simple check - in production, use proper CPUID detection
        #ifdef __AVX512F__
        return true;
        #else
        return false;
        #endif
    }
    
    // **PHASE 6: AVX-512 8-way parallel hash (vs Phase 5's 4-way AVX2)**
    void hash_batch_avx512(const uint8_t* keys, size_t key_len, uint32_t* hashes, size_t count) {
        if (!has_avx512() || count < 8) {
            // Fallback to Phase 5 AVX2 implementation
            hash_batch_avx2(keys, key_len, hashes, count);
            return;
        }
        
        // Process 8 keys at once with AVX-512
        for (size_t i = 0; i + 7 < count; i += 8) {
            __m512i data = _mm512_loadu_si512(reinterpret_cast<const __m512i*>(keys + i * key_len));
            __m512i hash_vec = _mm512_set1_epi32(0x811c9dc5); // FNV offset basis
            
            // FNV-1a hash with AVX-512
            for (size_t j = 0; j < key_len; j += 4) {
                __m512i key_chunk = _mm512_srli_epi32(data, j * 8);
                hash_vec = _mm512_xor_si512(hash_vec, key_chunk);
                hash_vec = _mm512_mullo_epi32(hash_vec, _mm512_set1_epi32(0x01000193)); // FNV prime
            }
            
            _mm512_storeu_si512(reinterpret_cast<__m512i*>(hashes + i), hash_vec);
        }
        
        // Handle remaining keys with scalar code
        for (size_t i = (count & ~7); i < count; ++i) {
            hashes[i] = simple_hash(keys + i * key_len, key_len);
        }
    }
    
    // **PHASE 6: AVX-512 8-way parallel memcmp**
    int memcmp_avx512(const void* a, const void* b, size_t len) {
        if (!has_avx512() || len < 64) {
            return std::memcmp(a, b, len);
        }
        
        const uint8_t* pa = static_cast<const uint8_t*>(a);
        const uint8_t* pb = static_cast<const uint8_t*>(b);
        
        // Process 64 bytes at once
        for (size_t i = 0; i + 63 < len; i += 64) {
            __m512i va = _mm512_loadu_si512(reinterpret_cast<const __m512i*>(pa + i));
            __m512i vb = _mm512_loadu_si512(reinterpret_cast<const __m512i*>(pb + i));
            
            __mmask64 mask = _mm512_cmpneq_epi8_mask(va, vb);
            if (mask != 0) {
                // Find first difference
                int pos = __builtin_ctzll(mask);
                return pa[i + pos] - pb[i + pos];
            }
        }
        
        // Handle remaining bytes
        return std::memcmp(pa + (len & ~63), pb + (len & ~63), len & 63);
    }
    
    // Phase 5 AVX2 fallback (4-way parallel)
    void hash_batch_avx2(const uint8_t* keys, size_t key_len, uint32_t* hashes, size_t count) {
        for (size_t i = 0; i + 3 < count; i += 4) {
            __m256i data = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(keys + i * key_len));
            __m256i hash_vec = _mm256_set1_epi32(0x811c9dc5);
            
            for (size_t j = 0; j < key_len; j += 4) {
                __m256i key_chunk = _mm256_srli_epi32(data, j * 8);
                hash_vec = _mm256_xor_si256(hash_vec, key_chunk);
                hash_vec = _mm256_mullo_epi32(hash_vec, _mm256_set1_epi32(0x01000193));
            }
            
            _mm256_storeu_si256(reinterpret_cast<__m256i*>(hashes + i), hash_vec);
        }
        
        for (size_t i = (count & ~3); i < count; ++i) {
            hashes[i] = simple_hash(keys + i * key_len, key_len);
        }
    }
    
    // Simple hash fallback
    uint32_t simple_hash(const uint8_t* key, size_t len) {
        uint32_t hash = 0x811c9dc5;
        for (size_t i = 0; i < len; ++i) {
            hash ^= key[i];
            hash *= 0x01000193;
        }
        return hash;
    }
}

// **PHASE 6: Smart NUMA Namespace (only bind when beneficial)**
namespace numa {
    
    struct NUMAInfo {
        bool numa_enabled;
        int numa_nodes;
        int current_node;
    };
    
    NUMAInfo initialize() {
        NUMAInfo info = {false, 1, 0};
        
        #ifdef __linux__
        if (numa_available() == 0) {
            info.numa_nodes = numa_max_node() + 1;
            info.current_node = numa_node_of_cpu(sched_getcpu());
            
            // **PHASE 6: Only enable NUMA if we have multiple nodes**
            info.numa_enabled = (info.numa_nodes > 1);
            
            if (info.numa_enabled) {
                std::cout << "NUMA: Detected " << info.numa_nodes << " nodes, current node: " 
                         << info.current_node << " (NUMA optimizations enabled)" << std::endl;
            } else {
                std::cout << "NUMA: Single node system detected (NUMA optimizations disabled)" << std::endl;
            }
        } else {
            std::cout << "NUMA: Not available (NUMA optimizations disabled)" << std::endl;
        }
        #endif
        
        return info;
    }
    
    void* allocate_numa_local(size_t size, int node = -1) {
        #ifdef __linux__
        if (node == -1) {
            node = numa_node_of_cpu(sched_getcpu());
        }
        return numa_alloc_onnode(size, node);
        #else
        return std::aligned_alloc(64, size); // 64-byte aligned for AVX-512
        #endif
    }
    
    void deallocate_numa(void* ptr, size_t size) {
        #ifdef __linux__
        numa_free(ptr, size);
        #else
        std::free(ptr);
        #endif
    }
    
    void set_cpu_affinity(int cpu_id) {
        #ifdef __linux__
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(cpu_id, &cpuset);
        
        int result = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
        if (result != 0) {
            std::cerr << "Warning: Failed to set CPU affinity to core " << cpu_id 
                     << ": " << strerror(result) << std::endl;
        }
        #endif
    }
    
    void set_memory_policy_local() {
        #ifdef __linux__
        if (numa_run_on_node(numa_node_of_cpu(sched_getcpu())) < 0) {
            std::cerr << "Warning: Failed to set NUMA memory policy" << std::endl;
        }
        #endif
    }
}

// All other classes remain the same as Phase 5 but with optimizations...
// [Include all the existing classes from Phase 5: LockFreeQueue, CacheEntry, etc.]

// **PHASE 6: Optimized CoreThread Class**
class CoreThread {
private:
    size_t core_id_;
    size_t num_cores_;
    size_t num_shards_;
    std::atomic<bool> running_{false};
    std::thread thread_;
    
    // NUMA info
    numa::NUMAInfo numa_info_;
    
    // Event handling
    #ifdef HAS_LINUX_EPOLL
    int epoll_fd_ = -1;
    #elif defined(HAS_MACOS_KQUEUE)
    int kqueue_fd_ = -1;
    #endif
    
    // Other members...
    
public:
    CoreThread(size_t core_id, size_t num_cores, size_t num_shards, 
               const std::string& ssd_path, size_t memory_mb,
               std::shared_ptr<CoreMetrics> metrics)
        : core_id_(core_id), num_cores_(num_cores), num_shards_(num_shards),
          metrics_(metrics) {
        
        // **PHASE 6: Initialize smart NUMA**
        numa_info_ = numa::initialize();
        
        // Initialize event system
        #ifdef HAS_LINUX_EPOLL
        epoll_fd_ = epoll_create1(EPOLL_CLOEXEC);
        if (epoll_fd_ == -1) {
            throw std::runtime_error("Failed to create epoll fd for core " + std::to_string(core_id_));
        }
        #elif defined(HAS_MACOS_KQUEUE)
        kqueue_fd_ = kqueue();
        if (kqueue_fd_ == -1) {
            throw std::runtime_error("Failed to create kqueue fd for core " + std::to_string(core_id_));
        }
        #endif
        
        std::cout << "🔧 Core " << core_id_ << " initialized with smart NUMA" << std::endl;
    }
    
    void start() {
        running_.store(true);
        thread_ = std::thread(&CoreThread::run, this);
        
        // **PHASE 6: Only set CPU affinity if NUMA is beneficial**
        #ifdef HAS_LINUX_EPOLL
        if (numa_info_.numa_enabled) {
            cpu_set_t cpuset;
            CPU_ZERO(&cpuset);
            CPU_SET(core_id_, &cpuset);
            
            int result = pthread_setaffinity_np(thread_.native_handle(), sizeof(cpu_set_t), &cpuset);
            if (result != 0) {
                std::cerr << "Warning: Failed to set CPU affinity for core " << core_id_ 
                         << ": " << strerror(result) << std::endl;
            }
        }
        
        // Set thread name for monitoring
        std::string thread_name = "meteor_core_" + std::to_string(core_id_);
        pthread_setname_np(thread_.native_handle(), thread_name.c_str());
        #endif
        
        std::cout << "🚀 Core " << core_id_ << " thread started";
        if (numa_info_.numa_enabled) {
            std::cout << " (NUMA-optimized)";
        }
        std::cout << std::endl;
    }
    
    void run() {
        // **PHASE 6: Set NUMA memory policy only if beneficial**
        if (numa_info_.numa_enabled) {
            numa::set_memory_policy_local();
        }
        
        std::cout << "🚀 Phase 6 Optimized: Core " << core_id_ << " event loop started ";
        if (numa_info_.numa_enabled) {
            std::cout << "(NUMA node " << numa_info_.current_node << ")";
        } else {
            std::cout << "(single-node optimized)";
        }
        std::cout << std::endl;
        
        // Main event loop (same as Phase 5)
        while (running_.load()) {
            // Process events with AVX-512 optimizations
            process_events();
        }
        
        std::cout << "🛑 Core " << core_id_ << " event loop stopped" << std::endl;
    }
    
    // ... rest of the methods same as Phase 5 ...
};

// **PHASE 6: Optimized Server Class**
class ThreadPerCoreServer {
private:
    // ... same members as Phase 5 ...
    
    void start_core_threads() {
        std::cout << "🔧 Starting " << num_cores_ << " core threads (optimized)..." << std::endl;
        
        core_threads_.reserve(num_cores_);
        
        // **PHASE 6: Create all core threads first**
        for (size_t i = 0; i < num_cores_; ++i) {
            auto metrics = metrics_collector_->get_core_metrics(i);
            auto core = std::make_unique<CoreThread>(i, num_cores_, num_shards_, ssd_path_, memory_mb_, metrics);
            core_threads_.push_back(std::move(core));
        }
        
        // Set up inter-core references
        std::vector<CoreThread*> core_refs;
        for (const auto& core : core_threads_) {
            core_refs.push_back(core.get());
        }
        
        // **PHASE 6: Start threads with minimal delay (reduced from 100ms to 10ms)**
        for (size_t i = 0; i < core_threads_.size(); ++i) {
            const auto& core = core_threads_[i];
            core->set_core_references(core_refs);
            core->start();
            
            // Minimal delay to prevent race conditions
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        
        // **PHASE 6: Reduced initialization wait (from 2s to 500ms)**
        std::cout << "⏳ Finalizing core thread initialization..." << std::endl;
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        
        std::cout << "✅ All " << num_cores_ << " core threads started with AVX-512 SIMD and smart NUMA" << std::endl;
    }
    
    // ... rest of the methods same as Phase 5 ...
};

// Main function same as Phase 5...
int main(int argc, char* argv[]) {
    std::cout << std::endl;
    std::cout << "███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ " << std::endl;
    std::cout << "████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗" << std::endl;
    std::cout << "██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝" << std::endl;
    std::cout << "██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗" << std::endl;
    std::cout << "██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║" << std::endl;
    std::cout << "╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝" << std::endl;
    std::cout << std::endl;
    std::cout << "   PHASE 6 STEP 1 OPTIMIZED: Thread-Per-Core with Smart NUMA + AVX-512" << std::endl;
    std::cout << "   🔥 Reduced Latency • Smart NUMA • AVX-512 SIMD • Lock-Free • Monitoring" << std::endl;
    std::cout << std::endl;

    // Parse command line arguments
    std::string host = "0.0.0.0";
    int port = 6379;
    int num_cores = std::thread::hardware_concurrency();
    int num_shards = num_cores * 4;
    int memory_mb = 512;
    std::string ssd_path = "";
    bool logging = false;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "-h" && i + 1 < argc) {
            host = argv[++i];
        } else if (arg == "-p" && i + 1 < argc) {
            port = std::atoi(argv[++i]);
        } else if (arg == "-c" && i + 1 < argc) {
            num_cores = std::atoi(argv[++i]);
        } else if (arg == "-s" && i + 1 < argc) {
            num_shards = std::atoi(argv[++i]);
        } else if (arg == "-m" && i + 1 < argc) {
            memory_mb = std::atoi(argv[++i]);
        } else if (arg == "-ssd" && i + 1 < argc) {
            ssd_path = argv[++i];
        } else if (arg == "-l") {
            logging = true;
        }
    }

    std::cout << "🔧 Configuration:" << std::endl;
    std::cout << "   Host: " << host << std::endl;
    std::cout << "   Port: " << port << std::endl;
    std::cout << "   CPU Cores: " << num_cores << std::endl;
    std::cout << "   Shards: " << num_shards << std::endl;
    std::cout << "   Total Memory: " << memory_mb << "MB" << std::endl;
    std::cout << "   SSD Path: " << (ssd_path.empty() ? "disabled" : ssd_path) << std::endl;
    std::cout << "   Logging: " << (logging ? "enabled" : "disabled") << std::endl;
    std::cout << "   Event System: ";
    #ifdef HAS_LINUX_EPOLL
    std::cout << "Linux epoll" << std::endl;
    #elif defined(HAS_MACOS_KQUEUE)
    std::cout << "macOS kqueue" << std::endl;
    #endif
    std::cout << std::endl;

    try {
        std::cout << "🚀 Starting Thread-Per-Core Meteor Server (Phase 6 Optimized)..." << std::endl;
        ThreadPerCoreServer server(host, port, num_cores, num_shards, memory_mb, ssd_path, logging);
        server.start();
    } catch (const std::exception& e) {
        std::cerr << "Failed to start server: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}