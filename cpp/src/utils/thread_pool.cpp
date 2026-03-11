#include "../../include/utils/thread_pool.hpp"
#include <algorithm>
#include <chrono>
#include <iostream>

namespace meteor {
namespace utils {

ThreadPool::ThreadPool(size_t num_threads) 
    : shutdown_(false), active_tasks_(0), completed_tasks_(0) {
    
    if (num_threads == 0) {
        num_threads = std::thread::hardware_concurrency();
        if (num_threads == 0) num_threads = 4; // fallback
    }
    
    threads_.reserve(num_threads);
    
    for (size_t i = 0; i < num_threads; ++i) {
        threads_.emplace_back([this, i] {
            worker_thread(i);
        });
    }
}

ThreadPool::~ThreadPool() {
    shutdown();
}

void ThreadPool::shutdown() {
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        if (shutdown_.exchange(true)) {
            return; // Already shutdown
        }
    }
    
    condition_.notify_all();
    
    for (auto& thread : threads_) {
        if (thread.joinable()) {
            thread.join();
        }
    }
    
    threads_.clear();
}

void ThreadPool::wait_for_all_tasks() {
    std::unique_lock<std::mutex> lock(queue_mutex_);
    finished_.wait(lock, [this] {
        return tasks_.empty() && active_tasks_.load() == 0;
    });
}

size_t ThreadPool::get_queue_size() const {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    return tasks_.size();
}

void ThreadPool::resize(size_t num_threads) {
    if (num_threads == threads_.size()) {
        return;
    }
    
    shutdown();
    
    shutdown_.store(false);
    active_tasks_.store(0);
    
    threads_.clear();
    threads_.reserve(num_threads);
    
    for (size_t i = 0; i < num_threads; ++i) {
        threads_.emplace_back([this, i] {
            worker_thread(i);
        });
    }
}

void ThreadPool::worker_thread(size_t thread_id) {
    while (true) {
        std::function<void()> task;
        
        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            
            condition_.wait(lock, [this] {
                return shutdown_.load() || !tasks_.empty();
            });
            
            if (shutdown_.load() && tasks_.empty()) {
                break;
            }
            
            if (!tasks_.empty()) {
                task = std::move(tasks_.front());
                tasks_.pop();
                active_tasks_.fetch_add(1);
            }
        }
        
        if (task) {
            try {
                task();
            } catch (const std::exception& e) {
                // Log error but continue
                std::cerr << "ThreadPool: Task exception: " << e.what() << std::endl;
            } catch (...) {
                std::cerr << "ThreadPool: Unknown task exception" << std::endl;
            }
            
            active_tasks_.fetch_sub(1);
            completed_tasks_.fetch_add(1);
            
            // Notify waiting threads that a task completed
            finished_.notify_all();
        }
    }
}

// Template instantiation helpers
template<typename F, typename... Args>
auto ThreadPool::submit(F&& f, Args&&... args) -> std::future<typename std::invoke_result_t<F, Args...>> {
    using return_type = typename std::invoke_result_t<F, Args...>;
    
    auto task = std::make_shared<std::packaged_task<return_type()>>(
        std::bind(std::forward<F>(f), std::forward<Args>(args)...)
    );
    
    std::future<return_type> result = task->get_future();
    
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        
        if (shutdown_.load()) {
            throw std::runtime_error("ThreadPool is shutdown");
        }
        
        tasks_.emplace([task]() {
            (*task)();
        });
    }
    
    condition_.notify_one();
    return result;
}

template<typename F, typename... Args>
void ThreadPool::submit_detached(F&& f, Args&&... args) {
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        
        if (shutdown_.load()) {
            throw std::runtime_error("ThreadPool is shutdown");
        }
        
        tasks_.emplace([f = std::forward<F>(f), args...]() mutable {
            f(args...);
        });
    }
    
    condition_.notify_one();
}

// Explicit template instantiations for common use cases
template auto ThreadPool::submit<std::function<void()>>(std::function<void()>&&) -> std::future<void>;
template auto ThreadPool::submit<void(*)()>(void(*&&)()) -> std::future<void>;

} // namespace utils
} // namespace meteor 