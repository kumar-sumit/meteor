#pragma once

#include <vector>
#include <thread>
#include <queue>
#include <functional>
#include <mutex>
#include <condition_variable>
#include <atomic>

namespace meteor {
namespace utils {

struct FiberPoolConfig {
    size_t num_fibers = 8;
    bool enable_work_stealing = true;
    bool enable_numa_awareness = false;
};

class FiberPool {
public:
    explicit FiberPool(const FiberPoolConfig& config);
    ~FiberPool();
    
    void start();
    void stop();
    
    void submit(std::function<void()> task);
    size_t pending_tasks() const;
    
private:
    FiberPoolConfig config_;
    std::atomic<bool> running_;
    std::vector<std::thread> workers_;
    std::queue<std::function<void()>> tasks_;
    mutable std::mutex queue_mutex_;
    std::condition_variable condition_;
};

} // namespace utils
} // namespace meteor 