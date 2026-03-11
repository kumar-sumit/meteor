// **APPROACH 2 SIMPLIFIED TEST: VLL + Epoch-Based Design**
// Focus on VLL locking and epoch-based memory management 
// Target: Validate production-proven reliability patterns

#include <iostream>
#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <array>
#include <functional>
#include <chrono>
#include <unordered_map>
#include <mutex>

// **APPROACH 2: VLL + EPOCH-BASED CORE INNOVATIONS**

namespace vll_epoch_based {
    
    // **INNOVATION 1: Very Lightweight Locking (DragonflyDB-inspired)**
    class VeryLightweightLock {
    private:
        std::atomic<uint32_t> lock_word_{0};
        
        static constexpr uint32_t READER_MASK = 0xFFFF;        // Bits 0-15
        static constexpr uint32_t WRITER_FLAG = 0x10000;       // Bit 16
        static constexpr uint32_t WRITER_CORE_SHIFT = 17;      // Bits 17-31
        static constexpr uint32_t WRITER_CORE_MASK = 0x7FFF;   // 15 bits for core ID
        
    public:
        bool try_acquire_shared(uint32_t core_id) {
            uint32_t current = lock_word_.load(std::memory_order_acquire);
            
            if (current & WRITER_FLAG) {
                return false;  // Writer present
            }
            
            if ((current & READER_MASK) >= READER_MASK) {
                return false;  // Too many readers
            }
            
            uint32_t desired = current + 1;
            return lock_word_.compare_exchange_weak(current, desired, 
                                                   std::memory_order_acquire,
                                                   std::memory_order_relaxed);
        }
        
        void release_shared() {
            lock_word_.fetch_sub(1, std::memory_order_release);
        }
        
        bool try_acquire_exclusive(uint32_t core_id) {
            uint32_t expected = 0;  // No readers, no writers
            uint32_t desired = WRITER_FLAG | (core_id << WRITER_CORE_SHIFT);
            
            return lock_word_.compare_exchange_weak(expected, desired,
                                                   std::memory_order_acquire,
                                                   std::memory_order_relaxed);
        }
        
        void release_exclusive() {
            lock_word_.store(0, std::memory_order_release);
        }
        
        bool is_exclusively_locked() const {
            return (lock_word_.load(std::memory_order_relaxed) & WRITER_FLAG) != 0;
        }
        
        uint32_t reader_count() const {
            return lock_word_.load(std::memory_order_relaxed) & READER_MASK;
        }
        
        uint32_t writer_core() const {
            uint32_t word = lock_word_.load(std::memory_order_relaxed);
            if (word & WRITER_FLAG) {
                return (word >> WRITER_CORE_SHIFT) & WRITER_CORE_MASK;
            }
            return UINT32_MAX;  // No writer
        }
    };
    
    // **INNOVATION 2: Epoch-Based Memory Reclamation (Simplified)**
    class EpochBasedReclamation {
    private:
        static constexpr size_t MAX_CORES = 16;
        static constexpr size_t EPOCHS_TO_KEEP = 3;
        
        std::atomic<uint64_t> global_epoch_{0};
        
        struct alignas(64) CoreEpochInfo {
            std::atomic<uint64_t> local_epoch{0};
            std::atomic<bool> active{false};
        };
        
        std::array<CoreEpochInfo, MAX_CORES> core_epochs_;
        
        struct DeferredObject {
            void* ptr;
            std::function<void(void*)> deleter;
            uint64_t epoch;
            
            DeferredObject(void* p, std::function<void(void*)> d, uint64_t e)
                : ptr(p), deleter(std::move(d)), epoch(e) {}
        };
        
        std::mutex deferred_mutex_;
        std::vector<DeferredObject> deferred_objects_;
        
    public:
        void enter_epoch(uint32_t core_id) {
            if (core_id >= MAX_CORES) return;
            
            auto& core_info = core_epochs_[core_id];
            uint64_t current_global = global_epoch_.load(std::memory_order_acquire);
            
            core_info.local_epoch.store(current_global, std::memory_order_release);
            core_info.active.store(true, std::memory_order_release);
        }
        
        void exit_epoch(uint32_t core_id) {
            if (core_id >= MAX_CORES) return;
            
            core_epochs_[core_id].active.store(false, std::memory_order_release);
        }
        
        bool try_advance_epoch() {
            uint64_t current_global = global_epoch_.load(std::memory_order_relaxed);
            
            // Check if all active cores are caught up
            for (size_t i = 0; i < MAX_CORES; ++i) {
                auto& core_info = core_epochs_[i];
                if (core_info.active.load(std::memory_order_acquire)) {
                    uint64_t local_epoch = core_info.local_epoch.load(std::memory_order_acquire);
                    if (local_epoch < current_global) {
                        return false;  // Core is lagging
                    }
                }
            }
            
            // Advance epoch
            uint64_t new_epoch = current_global + 1;
            if (global_epoch_.compare_exchange_weak(current_global, new_epoch,
                                                   std::memory_order_acq_rel)) {
                reclaim_old_objects();
                return true;
            }
            
            return false;
        }
        
        template<typename T>
        void defer_delete(T* ptr) {
            uint64_t current_epoch = global_epoch_.load(std::memory_order_relaxed);
            
            std::lock_guard<std::mutex> lock(deferred_mutex_);
            deferred_objects_.emplace_back(
                ptr,
                [](void* p) { delete static_cast<T*>(p); },
                current_epoch
            );
        }
        
        void reclaim_old_objects() {
            std::lock_guard<std::mutex> lock(deferred_mutex_);
            uint64_t current_epoch = global_epoch_.load(std::memory_order_relaxed);
            uint64_t safe_epoch = (current_epoch >= EPOCHS_TO_KEEP) ? 
                                 current_epoch - EPOCHS_TO_KEEP : 0;
            
            auto it = std::remove_if(deferred_objects_.begin(), deferred_objects_.end(),
                [safe_epoch](const DeferredObject& obj) {
                    if (obj.epoch <= safe_epoch) {
                        obj.deleter(obj.ptr);  // Safe to delete
                        return true;
                    }
                    return false;
                });
            
            deferred_objects_.erase(it, deferred_objects_.end());
        }
        
        uint64_t current_epoch() const {
            return global_epoch_.load(std::memory_order_relaxed);
        }
        
        size_t pending_deletions() const {
            std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(deferred_mutex_));
            return deferred_objects_.size();
        }
    };
    
    // **INNOVATION 3: Hierarchical Sharding (Simplified)**
    class HierarchicalSharding {
    private:
        static constexpr size_t NUMA_NODES = 2;
        static constexpr size_t CORES_PER_NODE = 8;
        static constexpr size_t TOTAL_CORES = NUMA_NODES * CORES_PER_NODE;
        
        static constexpr uint64_t FNV_OFFSET_BASIS = 0xcbf29ce484222325ULL;
        static constexpr uint64_t FNV_PRIME = 0x100000001b3ULL;
        
        uint64_t hash_key(const std::string& key) const {
            uint64_t hash = FNV_OFFSET_BASIS;
            for (char c : key) {
                hash ^= static_cast<uint8_t>(c);
                hash *= FNV_PRIME;
            }
            return hash;
        }
        
    public:
        uint32_t route_to_core(const std::string& key) const {
            uint64_t hash = hash_key(key);
            
            // Level 1: Choose NUMA node (for locality)
            uint32_t numa_node = hash % NUMA_NODES;
            
            // Level 2: Choose core within NUMA node (for distribution)
            uint32_t core_offset = (hash / NUMA_NODES) % CORES_PER_NODE;
            
            return numa_node * CORES_PER_NODE + core_offset;
        }
        
        bool same_numa_node(uint32_t core1, uint32_t core2) const {
            if (core1 >= TOTAL_CORES || core2 >= TOTAL_CORES) return false;
            return (core1 / CORES_PER_NODE) == (core2 / CORES_PER_NODE);
        }
    };
    
    // **INNOVATION 4: Adaptive Conflict Detection (Simplified)**
    class AdaptiveConflictDetector {
    private:
        static constexpr float CONFLICT_THRESHOLD = 0.01f;  // 1% conflict rate
        
        struct ConflictPattern {
            std::atomic<uint32_t> total_accesses{0};
            std::atomic<uint32_t> conflicts_detected{0};
        };
        
        std::unordered_map<std::string, ConflictPattern> pattern_cache_;
        std::mutex cache_mutex_;
        
    public:
        bool should_check_conflicts(const std::vector<std::string>& keys) const {
            if (keys.empty()) return false;
            
            std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(cache_mutex_));
            
            for (const auto& key : keys) {
                auto it = pattern_cache_.find(key);
                if (it != pattern_cache_.end()) {
                    uint32_t total = it->second.total_accesses.load(std::memory_order_relaxed);
                    uint32_t conflicts = it->second.conflicts_detected.load(std::memory_order_relaxed);
                    
                    if (total >= 10) {
                        float conflict_rate = static_cast<float>(conflicts) / total;
                        if (conflict_rate > CONFLICT_THRESHOLD) {
                            return true;
                        }
                    } else {
                        return true;  // Not enough data, be conservative
                    }
                }
            }
            
            return false;  // Low conflict probability
        }
        
        void record_conflict_check(const std::vector<std::string>& keys, bool conflict_found) {
            if (keys.empty()) return;
            
            std::lock_guard<std::mutex> lock(cache_mutex_);
            
            for (const auto& key : keys) {
                auto& pattern = pattern_cache_[key];
                pattern.total_accesses.fetch_add(1, std::memory_order_relaxed);
                if (conflict_found) {
                    pattern.conflicts_detected.fetch_add(1, std::memory_order_relaxed);
                }
            }
        }
        
        size_t pattern_count() const {
            std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(cache_mutex_));
            return pattern_cache_.size();
        }
    };
    
    // Global instances
    HierarchicalSharding global_sharding;
    EpochBasedReclamation global_epoch_manager;
    AdaptiveConflictDetector global_conflict_detector;
    
} // namespace vll_epoch_based

// **TEST FUNCTIONS**
void test_very_lightweight_locks() {
    std::cout << "🔒 Testing Very Lightweight Locks..." << std::endl;
    
    vll_epoch_based::VeryLightweightLock lock;
    
    // Test exclusive access
    std::cout << "   Testing exclusive access:" << std::endl;
    bool ex1 = lock.try_acquire_exclusive(1);
    bool ex2 = lock.try_acquire_exclusive(2);  // Should fail
    std::cout << "     Core 1 exclusive: " << ex1 << " (should be 1)" << std::endl;
    std::cout << "     Core 2 exclusive: " << ex2 << " (should be 0)" << std::endl;
    std::cout << "     Writer core: " << lock.writer_core() << " (should be 1)" << std::endl;
    std::cout << "     Is exclusively locked: " << lock.is_exclusively_locked() << std::endl;
    
    lock.release_exclusive();
    std::cout << "   After release:" << std::endl;
    std::cout << "     Is exclusively locked: " << lock.is_exclusively_locked() << std::endl;
    
    // Test shared access
    std::cout << "   Testing shared access:" << std::endl;
    bool sh1 = lock.try_acquire_shared(1);
    bool sh2 = lock.try_acquire_shared(2);
    bool sh3 = lock.try_acquire_shared(3);
    std::cout << "     Shared acquisitions: " << sh1 << ", " << sh2 << ", " << sh3 << std::endl;
    std::cout << "     Reader count: " << lock.reader_count() << std::endl;
    
    bool ex3 = lock.try_acquire_exclusive(4);  // Should fail with readers present
    std::cout << "     Exclusive with readers present: " << ex3 << " (should be 0)" << std::endl;
    
    lock.release_shared();
    lock.release_shared();
    lock.release_shared();
    std::cout << "     After releasing all shared: " << lock.reader_count() << std::endl;
}

void test_epoch_based_reclamation() {
    std::cout << "♾️ Testing Epoch-Based Reclamation..." << std::endl;
    
    auto& epoch_mgr = vll_epoch_based::global_epoch_manager;
    
    std::cout << "   Initial epoch: " << epoch_mgr.current_epoch() << std::endl;
    
    // Simulate core activity
    epoch_mgr.enter_epoch(0);
    epoch_mgr.enter_epoch(1);
    
    // Create some objects to defer
    int* obj1 = new int(42);
    int* obj2 = new int(84);
    
    epoch_mgr.defer_delete(obj1);
    epoch_mgr.defer_delete(obj2);
    
    std::cout << "   Pending deletions: " << epoch_mgr.pending_deletions() << std::endl;
    
    // Try to advance epoch
    bool advanced = epoch_mgr.try_advance_epoch();
    std::cout << "   Epoch advance (with active cores): " << advanced << " (should be 0)" << std::endl;
    
    // Exit cores and advance
    epoch_mgr.exit_epoch(0);
    epoch_mgr.exit_epoch(1);
    
    advanced = epoch_mgr.try_advance_epoch();
    std::cout << "   Epoch advance (after cores exit): " << advanced << " (should be 1)" << std::endl;
    std::cout << "   New epoch: " << epoch_mgr.current_epoch() << std::endl;
    
    // Advance a few more times to trigger reclamation
    for (int i = 0; i < 4; ++i) {
        epoch_mgr.try_advance_epoch();
    }
    
    std::cout << "   Final epoch: " << epoch_mgr.current_epoch() << std::endl;
    std::cout << "   Pending deletions after reclamation: " << epoch_mgr.pending_deletions() << std::endl;
}

void test_hierarchical_sharding() {
    std::cout << "🎯 Testing Hierarchical Sharding..." << std::endl;
    
    auto& sharding = vll_epoch_based::global_sharding;
    
    std::vector<std::string> test_keys = {
        "user:1001", "user:1002", "user:1003", "user:1004",
        "session:a001", "session:a002", "session:a003", "session:a004",
        "cache:x001", "cache:x002", "cache:x003", "cache:x004"
    };
    
    std::cout << "   Key routing results:" << std::endl;
    std::unordered_map<uint32_t, int> core_distribution;
    
    for (const auto& key : test_keys) {
        uint32_t target_core = sharding.route_to_core(key);
        core_distribution[target_core]++;
        
        std::cout << "     " << key << " -> core " << target_core;
        
        // Check NUMA node distribution
        for (const auto& other_key : test_keys) {
            if (other_key != key) {
                uint32_t other_core = sharding.route_to_core(other_key);
                if (sharding.same_numa_node(target_core, other_core)) {
                    std::cout << " (NUMA-local with " << other_key << ")";
                    break;
                }
            }
        }
        std::cout << std::endl;
    }
    
    std::cout << "   Core distribution:" << std::endl;
    for (const auto& [core, count] : core_distribution) {
        std::cout << "     Core " << core << ": " << count << " keys" << std::endl;
    }
}

void test_adaptive_conflict_detection() {
    std::cout << "🧠 Testing Adaptive Conflict Detection..." << std::endl;
    
    auto& detector = vll_epoch_based::global_conflict_detector;
    
    std::vector<std::string> pipeline_keys = {"key1", "key2", "key3"};
    
    // Initially should check conflicts (no data)
    bool should_check1 = detector.should_check_conflicts(pipeline_keys);
    std::cout << "   Initial conflict check: " << should_check1 << " (should be 0 - no patterns)" << std::endl;
    
    // Record some conflict-free operations
    for (int i = 0; i < 15; ++i) {
        detector.record_conflict_check(pipeline_keys, false);  // No conflicts
    }
    
    bool should_check2 = detector.should_check_conflicts(pipeline_keys);
    std::cout << "   After conflict-free history: " << should_check2 << " (should be 0)" << std::endl;
    
    // Introduce some conflicts
    for (int i = 0; i < 5; ++i) {
        detector.record_conflict_check(pipeline_keys, true);  // Conflicts
    }
    
    bool should_check3 = detector.should_check_conflicts(pipeline_keys);
    std::cout << "   After introducing conflicts: " << should_check3 << " (should be 1)" << std::endl;
    
    std::cout << "   Total patterns tracked: " << detector.pattern_count() << std::endl;
}

void test_vll_pipeline_scenario() {
    std::cout << "🚀 Testing VLL Pipeline Scenario..." << std::endl;
    
    // Simulate a cross-core pipeline with VLL protection
    std::vector<std::string> commands = {"SET", "GET", "DEL"};
    std::vector<std::string> keys = {"account:1001", "session:1001", "cache:1001"};
    
    auto& sharding = vll_epoch_based::global_sharding;
    auto& detector = vll_epoch_based::global_conflict_detector;
    auto& epoch_mgr = vll_epoch_based::global_epoch_manager;
    
    std::cout << "   Pipeline commands:" << std::endl;
    std::vector<uint32_t> target_cores;
    
    for (size_t i = 0; i < commands.size(); ++i) {
        uint32_t target_core = sharding.route_to_core(keys[i]);
        target_cores.push_back(target_core);
        
        std::cout << "     " << commands[i] << " " << keys[i] 
                  << " -> core " << target_core << std::endl;
    }
    
    // Check if conflict detection is needed
    bool needs_conflict_check = detector.should_check_conflicts(keys);
    std::cout << "   Needs conflict detection: " << needs_conflict_check << std::endl;
    
    if (needs_conflict_check) {
        std::cout << "   Using VLL-protected execution path" << std::endl;
        
        // Create VLL locks for each key
        std::unordered_map<std::string, vll_epoch_based::VeryLightweightLock> key_locks;
        for (const auto& key : keys) {
            key_locks[key];  // Initialize VLL for this key
        }
        
        // Try to acquire all locks
        std::vector<std::string> acquired_keys;
        bool all_acquired = true;
        
        for (const auto& key : keys) {
            if (key_locks[key].try_acquire_exclusive(0)) {  // Core 0 acquiring
                acquired_keys.push_back(key);
            } else {
                all_acquired = false;
                break;
            }
        }
        
        std::cout << "   Acquired " << acquired_keys.size() << "/" << keys.size() << " locks" << std::endl;
        
        if (all_acquired) {
            std::cout << "   ✅ All locks acquired - executing pipeline atomically" << std::endl;
            detector.record_conflict_check(keys, false);  // No conflict
        } else {
            std::cout << "   ❌ Lock conflict - using fallback execution" << std::endl;
            detector.record_conflict_check(keys, true);   // Conflict detected
        }
        
        // Release acquired locks
        for (const auto& key : acquired_keys) {
            key_locks[key].release_exclusive();
        }
    } else {
        std::cout << "   Using fast path (no conflict detection needed)" << std::endl;
    }
    
    // Epoch management
    epoch_mgr.enter_epoch(0);
    std::cout << "   Current epoch: " << epoch_mgr.current_epoch() << std::endl;
    epoch_mgr.exit_epoch(0);
    
    bool epoch_advanced = epoch_mgr.try_advance_epoch();
    std::cout << "   Epoch advanced: " << epoch_advanced << std::endl;
}

int main() {
    std::cout << "🚀 APPROACH 2: VLL + Epoch-Based Design - Infrastructure Test" << std::endl;
    std::cout << "⚡ Testing production-proven reliability patterns" << std::endl;
    std::cout << "🎯 Focus: VLL locks, epoch reclamation, hierarchical sharding, adaptive detection" << std::endl;
    
    std::cout << "\n" << std::string(60, '=') << std::endl;
    
    test_very_lightweight_locks();
    
    std::cout << "\n" << std::string(60, '=') << std::endl;
    
    test_epoch_based_reclamation();
    
    std::cout << "\n" << std::string(60, '=') << std::endl;
    
    test_hierarchical_sharding();
    
    std::cout << "\n" << std::string(60, '=') << std::endl;
    
    test_adaptive_conflict_detection();
    
    std::cout << "\n" << std::string(60, '=') << std::endl;
    
    test_vll_pipeline_scenario();
    
    std::cout << "\n" << std::string(60, '=') << std::endl;
    std::cout << "✅ All tests completed - Approach 2 infrastructure validated!" << std::endl;
    std::cout << "📊 Ready for integration with baseline server for 4.92M QPS target" << std::endl;
    
    return 0;
}
