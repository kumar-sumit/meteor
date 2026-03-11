#pragma once

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <future>
#include <memory>
#include <mutex>
#include <optional>
#include <queue>
#include <shared_mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#ifdef __linux__
struct io_uring_params;
struct io_uring_cqe;
struct io_uring_sqe;
#endif

namespace meteor {
namespace utils {
class BufferPool;
}

namespace storage {

struct FileInfo {
    int fd;
    std::string path;
    size_t size;
};

struct StorageStats {
    std::atomic<uint64_t> reads{0};
    std::atomic<uint64_t> writes{0};
    std::atomic<uint64_t> errors{0};
    std::atomic<uint64_t> bytes_read{0};
    std::atomic<uint64_t> bytes_written{0};
};

enum class IOType {
    READ,
    WRITE
};

struct IORequest {
    uint64_t id;
    IOType type;
    int fd;
    size_t offset;
    std::shared_ptr<uint8_t[]> buffer;
    std::string key;
    std::shared_ptr<std::promise<std::optional<std::string>>> completion;
};

class OptimizedSSDStorage {
public:
    OptimizedSSDStorage(const std::string& base_dir, size_t page_size, size_t max_file_size);
    ~OptimizedSSDStorage();

    // Disable copy and move
    OptimizedSSDStorage(const OptimizedSSDStorage&) = delete;
    OptimizedSSDStorage& operator=(const OptimizedSSDStorage&) = delete;
    OptimizedSSDStorage(OptimizedSSDStorage&&) = delete;
    OptimizedSSDStorage& operator=(OptimizedSSDStorage&&) = delete;

    // Async I/O operations
    std::optional<std::string> read_async(const std::string& key);
    bool write_async(const std::string& key, const std::string& value, 
                    std::chrono::seconds ttl = std::chrono::seconds{3600});

    // Synchronization
    void sync();
    void stop();

    // Statistics
    StorageStats get_stats() const;

private:
    // Configuration
    std::string base_dir_;
    size_t page_size_;
    size_t max_file_size_;

    // File management
    std::unordered_map<std::string, FileInfo> open_files_;
    mutable std::shared_mutex files_mutex_;

    // Async I/O backend
    bool init_io_backend();
    void cleanup_io_backend();

#ifdef __linux__
    // io_uring support
    bool use_io_uring_ = false;
    int io_uring_fd_ = -1;
    void* sq_ring_ = nullptr;
    void* cq_ring_ = nullptr;
    void* sqes_ = nullptr;
    
    // Ring buffer pointers
    uint32_t* sq_head_ = nullptr;
    uint32_t* sq_tail_ = nullptr;
    uint32_t sq_mask_ = 0;
    uint32_t sq_entries_ = 0;
    uint32_t* sq_array_ = nullptr;
    
    uint32_t* cq_head_ = nullptr;
    uint32_t* cq_tail_ = nullptr;
    uint32_t cq_mask_ = 0;
    uint32_t cq_entries_ = 0;
    io_uring_cqe* cqes_ = nullptr;
    
    bool init_io_uring();
    void cleanup_io_uring();
#endif

#ifdef __APPLE__
    // kqueue support
    bool use_kqueue_ = false;
    int kqueue_fd_ = -1;
    
    bool init_kqueue();
    void cleanup_kqueue();
#endif

    // Buffer management
    std::unique_ptr<utils::BufferPool> buffer_pool_;

    // Worker threads
    std::vector<std::thread> io_workers_;
    std::atomic<bool> running_;
    
    // Request management
    std::queue<std::shared_ptr<IORequest>> work_queue_;
    std::mutex work_queue_mutex_;
    std::condition_variable work_queue_cv_;
    
    std::unordered_map<uint64_t, std::shared_ptr<IORequest>> pending_requests_;
    std::mutex pending_requests_mutex_;
    std::atomic<uint64_t> next_request_id_;

    // Statistics
    std::atomic<uint64_t> read_count_{0};
    std::atomic<uint64_t> write_count_{0};
    std::atomic<uint64_t> error_count_{0};
    std::atomic<uint64_t> bytes_read_{0};
    std::atomic<uint64_t> bytes_written_{0};

    // Private methods
    std::optional<FileInfo> get_or_create_file(const std::string& key);
    std::string get_filename(const std::string& key) const;
    size_t calculate_position(const std::string& key) const;
    
    std::shared_ptr<uint8_t[]> prepare_write_data(const std::string& key, 
                                                 const std::string& value, 
                                                 std::chrono::seconds ttl);
    std::optional<std::string> parse_read_data(const std::shared_ptr<uint8_t[]>& buffer, 
                                              const std::string& expected_key);
    
    void submit_io_request(std::shared_ptr<IORequest> request);
    void io_worker();
    void process_io_request(std::shared_ptr<IORequest> request);
    void process_read_request(std::shared_ptr<IORequest> request);
    void process_write_request(std::shared_ptr<IORequest> request);
};

} // namespace storage
} // namespace meteor 