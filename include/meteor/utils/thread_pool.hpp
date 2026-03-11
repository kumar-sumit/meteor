#pragma once

#include <atomic>
#include <condition_variable>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>
#include <type_traits>

namespace meteor {
namespace utils {

class ThreadPool {
public:
    explicit ThreadPool(size_t num_threads = std::thread::hardware_concurrency());
    ~ThreadPool();

    // Disable copy and move
    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;
    ThreadPool(ThreadPool&&) = delete;
    ThreadPool& operator=(ThreadPool&&) = delete;

    // Enqueue a task and return a future
    template<class F, class... Args>
    auto enqueue(F&& f, Args&&... args) 
        -> std::future<std::invoke_result_t<F, Args...>>;

    // Get the number of threads
    size_t size() const { return threads_.size(); }

    // Get the number of pending tasks
    size_t pending_tasks() const;

    // Stop the thread pool
    void stop();

private:
    // Worker threads
    std::vector<std::thread> threads_;
    
    // Task queue
    std::queue<std::function<void()>> tasks_;
    
    // Synchronization
    std::mutex queue_mutex_;
    std::condition_variable condition_;
    std::atomic<bool> stop_flag_{false};
    
    // Statistics
    std::atomic<size_t> pending_count_{0};
    std::atomic<size_t> completed_count_{0};
};

// Template implementation
template<class F, class... Args>
auto ThreadPool::enqueue(F&& f, Args&&... args) 
    -> std::future<std::invoke_result_t<F, Args...>> {
    
    using return_type = std::invoke_result_t<F, Args...>;
    
    auto task = std::make_shared<std::packaged_task<return_type()>>(
        std::bind(std::forward<F>(f), std::forward<Args>(args)...)
    );
    
    std::future<return_type> result = task->get_future();
    
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        
        if (stop_flag_) {
            // Return a future with an exception instead of throwing
            std::promise<return_type> promise;
            promise.set_exception(std::make_exception_ptr(std::runtime_error("ThreadPool stopped")));
            return promise.get_future();
        }
        
        tasks_.emplace([task]() { (*task)(); });
        pending_count_++;
    }
    
    condition_.notify_one();
    return result;
}

} // namespace utils
} // namespace meteor 