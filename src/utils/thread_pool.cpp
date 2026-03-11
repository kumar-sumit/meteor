#include "meteor/utils/thread_pool.hpp"
#include <iostream>

namespace meteor {
namespace utils {

ThreadPool::ThreadPool(size_t num_threads) {
    if (num_threads == 0) {
        num_threads = std::thread::hardware_concurrency();
    }
    
    threads_.reserve(num_threads);
    
    for (size_t i = 0; i < num_threads; ++i) {
        threads_.emplace_back([this] {
            while (true) {
                std::function<void()> task;
                
                {
                    std::unique_lock<std::mutex> lock(queue_mutex_);
                    
                    condition_.wait(lock, [this] {
                        return stop_flag_ || !tasks_.empty();
                    });
                    
                    if (stop_flag_ && tasks_.empty()) {
                        return;
                    }
                    
                    task = std::move(tasks_.front());
                    tasks_.pop();
                    pending_count_--;
                }
                
                try {
                    task();
                    completed_count_++;
                } catch (const std::exception& e) {
                    std::cerr << "ThreadPool task exception: " << e.what() << std::endl;
                } catch (...) {
                    std::cerr << "ThreadPool task unknown exception" << std::endl;
                }
            }
        });
    }
}

ThreadPool::~ThreadPool() {
    stop();
}

void ThreadPool::stop() {
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        stop_flag_ = true;
    }
    
    condition_.notify_all();
    
    for (std::thread& thread : threads_) {
        if (thread.joinable()) {
            thread.join();
        }
    }
    
    threads_.clear();
}

size_t ThreadPool::pending_tasks() const {
    return pending_count_.load();
}

} // namespace utils
} // namespace meteor 