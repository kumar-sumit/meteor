#include "../../include/utils/fiber_pool.hpp"
#include <algorithm>

namespace meteor {
namespace utils {

FiberPool::FiberPool(const FiberPoolConfig& config) : config_(config), running_(false) {}

FiberPool::~FiberPool() {
    stop();
}

void FiberPool::start() {
    running_ = true;
    // Simple thread pool implementation for now
    for (size_t i = 0; i < config_.num_fibers; ++i) {
        workers_.emplace_back([this]() {
            while (running_) {
                std::function<void()> task;
                {
                    std::unique_lock<std::mutex> lock(queue_mutex_);
                    condition_.wait(lock, [this] { return !tasks_.empty() || !running_; });
                    
                    if (!running_) break;
                    
                    task = std::move(tasks_.front());
                    tasks_.pop();
                }
                
                task();
            }
        });
    }
}

void FiberPool::stop() {
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        running_ = false;
    }
    condition_.notify_all();
    
    for (auto& worker : workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    workers_.clear();
}

void FiberPool::submit(std::function<void()> task) {
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        if (!running_) return;
        tasks_.push(std::move(task));
    }
    condition_.notify_one();
}

size_t FiberPool::pending_tasks() const {
    std::unique_lock<std::mutex> lock(queue_mutex_);
    return tasks_.size();
}

} // namespace utils
} // namespace meteor 