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

// High-performance thread pool with work-stealing
class ThreadPool {
public:
    explicit ThreadPool(size_t num_threads = 0);
    ~ThreadPool();
    
    // Non-copyable, non-movable
    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;
    ThreadPool(ThreadPool&&) = delete;
    ThreadPool& operator=(ThreadPool&&) = delete;
    
    // Submit task and return future
    template<typename F, typename... Args>
    auto submit(F&& f, Args&&... args) -> std::future<typename std::invoke_result_t<F, Args...>>;
    
    // Submit task without future (fire-and-forget)
    template<typename F, typename... Args>
    void submit_detached(F&& f, Args&&... args);
    
    // Pool management
    void resize(size_t num_threads);
    void shutdown();
    void wait_for_all_tasks();
    
    // Statistics
    size_t get_thread_count() const { return threads_.size(); }
    size_t get_queue_size() const;
    size_t get_active_tasks() const { return active_tasks_.load(); }
    uint64_t get_completed_tasks() const { return completed_tasks_.load(); }
    
    // Health check
    bool is_running() const { return !shutdown_.load(); }

private:
    // Task wrapper
    class Task {
    public:
        virtual ~Task() = default;
        virtual void execute() = 0;
    };
    
    template<typename F>
    class TaskImpl : public Task {
    public:
        explicit TaskImpl(F&& f) : func_(std::forward<F>(f)) {}
        void execute() override { func_(); }
    private:
        F func_;
    };
    
    // Worker thread data
    struct WorkerData {
        std::queue<std::unique_ptr<Task>> local_queue;
        std::mutex local_mutex;
        std::condition_variable local_cv;
        std::atomic<bool> has_work{false};
        size_t thread_id;
        
        explicit WorkerData(size_t id) : thread_id(id) {}
    };
    
    // Thread pool state
    std::vector<std::thread> threads_;
    std::vector<std::unique_ptr<WorkerData>> worker_data_;
    
    // Global task queue
    std::queue<std::unique_ptr<Task>> global_queue_;
    std::mutex global_mutex_;
    std::condition_variable global_cv_;
    
    // Control
    std::atomic<bool> shutdown_{false};
    std::atomic<size_t> active_tasks_{0};
    std::atomic<uint64_t> completed_tasks_{0};
    
    // Work-stealing
    std::atomic<size_t> next_worker_{0};
    
    // Internal methods
    void worker_thread(size_t worker_id);
    std::unique_ptr<Task> get_task(size_t worker_id);
    std::unique_ptr<Task> steal_task(size_t worker_id);
    void notify_workers();
    
    // Utility
    size_t get_optimal_thread_count() const;
};

// Template implementations
template<typename F, typename... Args>
auto ThreadPool::submit(F&& f, Args&&... args) -> std::future<typename std::invoke_result_t<F, Args...>> {
    using ReturnType = typename std::invoke_result_t<F, Args...>;
    
    auto task = std::make_shared<std::packaged_task<ReturnType()>>(
        std::bind(std::forward<F>(f), std::forward<Args>(args)...)
    );
    
    auto future = task->get_future();
    
    {
        std::lock_guard<std::mutex> lock(global_mutex_);
        if (shutdown_.load()) {
            throw std::runtime_error("ThreadPool is shutting down");
        }
        
        global_queue_.emplace(std::make_unique<TaskImpl<std::function<void()>>>(
            [task] { (*task)(); }
        ));
    }
    
    active_tasks_.fetch_add(1);
    notify_workers();
    
    return future;
}

template<typename F, typename... Args>
void ThreadPool::submit_detached(F&& f, Args&&... args) {
    {
        std::lock_guard<std::mutex> lock(global_mutex_);
        if (shutdown_.load()) {
            return;
        }
        
        global_queue_.emplace(std::make_unique<TaskImpl<std::function<void()>>>(
            std::bind(std::forward<F>(f), std::forward<Args>(args)...)
        ));
    }
    
    active_tasks_.fetch_add(1);
    notify_workers();
}

// Simple thread-safe queue for high-performance scenarios
template<typename T>
class LockFreeQueue {
public:
    LockFreeQueue() = default;
    ~LockFreeQueue() = default;
    
    // Non-copyable, non-movable
    LockFreeQueue(const LockFreeQueue&) = delete;
    LockFreeQueue& operator=(const LockFreeQueue&) = delete;
    LockFreeQueue(LockFreeQueue&&) = delete;
    LockFreeQueue& operator=(LockFreeQueue&&) = delete;
    
    void push(T item);
    bool try_pop(T& item);
    bool empty() const;
    size_t size() const;

private:
    struct Node {
        std::atomic<T*> data{nullptr};
        std::atomic<Node*> next{nullptr};
    };
    
    std::atomic<Node*> head_{new Node};
    std::atomic<Node*> tail_{head_.load()};
    std::atomic<size_t> size_{0};
};

// Worker thread for specific tasks
class Worker {
public:
    explicit Worker(std::function<void()> work_func);
    ~Worker();
    
    // Non-copyable, non-movable
    Worker(const Worker&) = delete;
    Worker& operator=(const Worker&) = delete;
    Worker(Worker&&) = delete;
    Worker& operator=(Worker&&) = delete;
    
    void start();
    void stop();
    void join();
    
    bool is_running() const { return running_.load(); }
    std::thread::id get_thread_id() const;

private:
    std::function<void()> work_func_;
    std::thread thread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> should_stop_{false};
    
    void worker_loop();
};

} // namespace utils
} // namespace meteor 