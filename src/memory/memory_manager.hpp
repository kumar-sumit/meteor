#pragma once

#include <atomic>
#include <cstddef>

namespace garuda {

// Memory Manager with LFRU cache
class MemoryManager {
public:
    explicit MemoryManager(size_t memory_limit = 0);
    ~MemoryManager();
    
    // Memory statistics
    size_t get_used_memory() const { return used_memory_.load(); }
    size_t get_peak_memory() const { return peak_memory_.load(); }
    size_t get_fragmented_memory() const { return fragmented_memory_.load(); }
    size_t get_memory_limit() const { return memory_limit_; }
    
    // Memory management
    void trigger_defragmentation();
    void trigger_eviction();
    
private:
    size_t memory_limit_;
    std::atomic<size_t> used_memory_{0};
    std::atomic<size_t> peak_memory_{0};
    std::atomic<size_t> fragmented_memory_{0};
};

} // namespace garuda