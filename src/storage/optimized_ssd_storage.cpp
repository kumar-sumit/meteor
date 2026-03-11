#include "meteor/storage/optimized_ssd_storage.hpp"
#include "meteor/utils/aligned_allocator.hpp"
#include <algorithm>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <iostream>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __linux__
#include <linux/io_uring.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#elif __APPLE__
#include <sys/event.h>
#include <sys/types.h>
#endif

namespace meteor {
namespace storage {

OptimizedSSDStorage::OptimizedSSDStorage(const std::string& base_dir, 
                                        size_t page_size, 
                                        size_t max_file_size)
    : base_dir_(base_dir)
    , page_size_(page_size)
    , max_file_size_(max_file_size)
    , running_(false)
    , next_request_id_(1)
{
    // Create base directory
    std::filesystem::create_directories(base_dir_);
    
    // Initialize async I/O backend
    if (!init_io_backend()) {
        throw std::runtime_error("Failed to initialize async I/O backend");
    }
    
    // Initialize buffer pool
    buffer_pool_ = std::make_unique<utils::BufferPool>(page_size_, 1024);
    
    // Start I/O worker threads
    size_t worker_count = std::max(2U, std::thread::hardware_concurrency() / 2);
    for (size_t i = 0; i < worker_count; ++i) {
        io_workers_.emplace_back(&OptimizedSSDStorage::io_worker, this);
    }
    
    running_ = true;
}

OptimizedSSDStorage::~OptimizedSSDStorage() {
    stop();
}

void OptimizedSSDStorage::stop() {
    if (!running_.exchange(false)) {
        return;
    }
    
    // Signal workers to stop
    for (auto& worker : io_workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    
    // Close all files
    for (auto& [path, file] : open_files_) {
        close(file.fd);
    }
    open_files_.clear();
    
    // Cleanup I/O backend
    cleanup_io_backend();
}

std::optional<std::string> OptimizedSSDStorage::read_async(const std::string& key) {
    auto file_info = get_or_create_file(key);
    if (!file_info.has_value()) {
        return std::nullopt;
    }
    
    size_t position = calculate_position(key);
    auto buffer = buffer_pool_->get_buffer();
    
    // Create read request
    auto request = std::make_shared<IORequest>();
    request->id = next_request_id_++;
    request->type = IOType::READ;
    request->fd = file_info->fd;
    request->offset = position;
    request->buffer = buffer;
    request->key = key;
    request->completion = std::make_shared<std::promise<std::optional<std::string>>>();
    
    // Submit request
    submit_io_request(request);
    
    // Wait for completion
    auto future = request->completion->get_future();
    auto status = future.wait_for(std::chrono::seconds(5));
    
    if (status == std::future_status::timeout) {
        return std::nullopt;
    }
    
    return future.get();
}

bool OptimizedSSDStorage::write_async(const std::string& key, const std::string& value, 
                                     std::chrono::seconds ttl) {
    auto file_info = get_or_create_file(key);
    if (!file_info.has_value()) {
        return false;
    }
    
    size_t position = calculate_position(key);
    auto buffer = prepare_write_data(key, value, ttl);
    
    // Create write request
    auto request = std::make_shared<IORequest>();
    request->id = next_request_id_++;
    request->type = IOType::WRITE;
    request->fd = file_info->fd;
    request->offset = position;
    request->buffer = buffer;
    request->key = key;
    request->completion = std::make_shared<std::promise<std::optional<std::string>>>();
    
    // Submit request
    submit_io_request(request);
    
    return true;
}

void OptimizedSSDStorage::sync() {
    // Sync all open files
    for (const auto& [path, file] : open_files_) {
        fsync(file.fd);
    }
}

StorageStats OptimizedSSDStorage::get_stats() const {
    StorageStats stats;
    stats.reads = read_count_;
    stats.writes = write_count_;
    stats.errors = error_count_;
    stats.bytes_read = bytes_read_;
    stats.bytes_written = bytes_written_;
    return stats;
}

bool OptimizedSSDStorage::init_io_backend() {
#ifdef __linux__
    return init_io_uring();
#elif __APPLE__
    return init_kqueue();
#else
    return false; // Unsupported platform
#endif
}

void OptimizedSSDStorage::cleanup_io_backend() {
#ifdef __linux__
    cleanup_io_uring();
#elif __APPLE__
    cleanup_kqueue();
#endif
}

#ifdef __linux__
bool OptimizedSSDStorage::init_io_uring() {
    // Try to initialize io_uring
    io_uring_params params = {};
    params.sq_entries = 256;
    params.cq_entries = 512;
    
    int ret = syscall(__NR_io_uring_setup, 256, &params);
    if (ret < 0) {
        std::cerr << "io_uring not available, falling back to sync I/O" << std::endl;
        use_io_uring_ = false;
        return true; // Continue with sync I/O
    }
    
    io_uring_fd_ = ret;
    use_io_uring_ = true;
    
    // Map submission queue
    size_t sq_size = params.sq_off.array + params.sq_entries * sizeof(uint32_t);
    sq_ring_ = mmap(nullptr, sq_size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE, 
                    io_uring_fd_, IORING_OFF_SQ_RING);
    
    if (sq_ring_ == MAP_FAILED) {
        close(io_uring_fd_);
        use_io_uring_ = false;
        return true;
    }
    
    // Map completion queue
    size_t cq_size = params.cq_off.cqes + params.cq_entries * sizeof(io_uring_cqe);
    cq_ring_ = mmap(nullptr, cq_size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE,
                    io_uring_fd_, IORING_OFF_CQ_RING);
    
    if (cq_ring_ == MAP_FAILED) {
        munmap(sq_ring_, sq_size);
        close(io_uring_fd_);
        use_io_uring_ = false;
        return true;
    }
    
    // Map submission queue entries
    size_t sqe_size = params.sq_entries * sizeof(io_uring_sqe);
    sqes_ = mmap(nullptr, sqe_size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE,
                 io_uring_fd_, IORING_OFF_SQES);
    
    if (sqes_ == MAP_FAILED) {
        munmap(sq_ring_, sq_size);
        munmap(cq_ring_, cq_size);
        close(io_uring_fd_);
        use_io_uring_ = false;
        return true;
    }
    
    // Initialize ring pointers
    sq_head_ = (uint32_t*)((char*)sq_ring_ + params.sq_off.head);
    sq_tail_ = (uint32_t*)((char*)sq_ring_ + params.sq_off.tail);
    sq_mask_ = *(uint32_t*)((char*)sq_ring_ + params.sq_off.ring_mask);
    sq_entries_ = *(uint32_t*)((char*)sq_ring_ + params.sq_off.ring_entries);
    sq_array_ = (uint32_t*)((char*)sq_ring_ + params.sq_off.array);
    
    cq_head_ = (uint32_t*)((char*)cq_ring_ + params.cq_off.head);
    cq_tail_ = (uint32_t*)((char*)cq_ring_ + params.cq_off.tail);
    cq_mask_ = *(uint32_t*)((char*)cq_ring_ + params.cq_off.ring_mask);
    cq_entries_ = *(uint32_t*)((char*)cq_ring_ + params.cq_off.ring_entries);
    cqes_ = (io_uring_cqe*)((char*)cq_ring_ + params.cq_off.cqes);
    
    return true;
}

void OptimizedSSDStorage::cleanup_io_uring() {
    if (use_io_uring_) {
        if (sqes_) munmap(sqes_, sq_entries_ * sizeof(io_uring_sqe));
        if (cq_ring_) munmap(cq_ring_, cq_entries_ * sizeof(io_uring_cqe));
        if (sq_ring_) munmap(sq_ring_, sq_entries_ * sizeof(uint32_t));
        if (io_uring_fd_ >= 0) close(io_uring_fd_);
    }
}
#endif

#ifdef __APPLE__
bool OptimizedSSDStorage::init_kqueue() {
    kqueue_fd_ = kqueue();
    if (kqueue_fd_ < 0) {
        std::cerr << "Failed to create kqueue" << std::endl;
        return false;
    }
    
    use_kqueue_ = true;
    return true;
}

void OptimizedSSDStorage::cleanup_kqueue() {
    if (use_kqueue_ && kqueue_fd_ >= 0) {
        close(kqueue_fd_);
    }
}
#endif

std::optional<FileInfo> OptimizedSSDStorage::get_or_create_file(const std::string& key) {
    std::string filename = get_filename(key);
    std::string filepath = base_dir_ + "/" + filename;
    
    // Check if file is already open
    {
        std::shared_lock<std::shared_mutex> lock(files_mutex_);
        auto it = open_files_.find(filepath);
        if (it != open_files_.end()) {
            return it->second;
        }
    }
    
    // Open file with O_DIRECT for better performance
    int flags = O_RDWR | O_CREAT;
#ifdef __linux__
    flags |= O_DIRECT;
#endif
    
    int fd = open(filepath.c_str(), flags, 0644);
    if (fd < 0) {
        return std::nullopt;
    }
    
    // Set file size
    if (ftruncate(fd, max_file_size_) != 0) {
        close(fd);
        return std::nullopt;
    }
    
    FileInfo file_info;
    file_info.fd = fd;
    file_info.path = filepath;
    file_info.size = max_file_size_;
    
    // Store in cache
    {
        std::unique_lock<std::shared_mutex> lock(files_mutex_);
        open_files_[filepath] = file_info;
    }
    
    return file_info;
}

std::string OptimizedSSDStorage::get_filename(const std::string& key) const {
    std::hash<std::string> hasher;
    size_t hash = hasher(key);
    return "cache_" + std::to_string(hash % 1000) + ".dat";
}

size_t OptimizedSSDStorage::calculate_position(const std::string& key) const {
    std::hash<std::string> hasher;
    size_t hash = hasher(key);
    return (hash % (max_file_size_ / page_size_)) * page_size_;
}

std::shared_ptr<uint8_t[]> OptimizedSSDStorage::prepare_write_data(const std::string& key, 
                                                                  const std::string& value, 
                                                                  std::chrono::seconds ttl) {
    size_t total_size = sizeof(uint32_t) + sizeof(uint32_t) + sizeof(uint64_t) + sizeof(uint32_t) + 
                       key.size() + value.size();
    
    // Align to page boundary
    size_t aligned_size = ((total_size + page_size_ - 1) / page_size_) * page_size_;
    
    auto buffer = std::shared_ptr<uint8_t[]>(new (std::align_val_t(page_size_)) uint8_t[aligned_size]);
    memset(buffer.get(), 0, aligned_size);
    
    size_t offset = 0;
    
    // Write key length
    *reinterpret_cast<uint32_t*>(buffer.get() + offset) = key.size();
    offset += sizeof(uint32_t);
    
    // Write value length
    *reinterpret_cast<uint32_t*>(buffer.get() + offset) = value.size();
    offset += sizeof(uint32_t);
    
    // Write timestamp
    auto now = std::chrono::system_clock::now();
    auto timestamp = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
    *reinterpret_cast<uint64_t*>(buffer.get() + offset) = timestamp;
    offset += sizeof(uint64_t);
    
    // Write TTL
    *reinterpret_cast<uint32_t*>(buffer.get() + offset) = ttl.count();
    offset += sizeof(uint32_t);
    
    // Write key
    memcpy(buffer.get() + offset, key.data(), key.size());
    offset += key.size();
    
    // Write value
    memcpy(buffer.get() + offset, value.data(), value.size());
    
    return buffer;
}

std::optional<std::string> OptimizedSSDStorage::parse_read_data(const std::shared_ptr<uint8_t[]>& buffer, 
                                                               const std::string& expected_key) {
    size_t offset = 0;
    
    // Read key length
    uint32_t key_len = *reinterpret_cast<const uint32_t*>(buffer.get() + offset);
    offset += sizeof(uint32_t);
    
    // Read value length
    uint32_t value_len = *reinterpret_cast<const uint32_t*>(buffer.get() + offset);
    offset += sizeof(uint32_t);
    
    // Read timestamp
    uint64_t timestamp = *reinterpret_cast<const uint64_t*>(buffer.get() + offset);
    offset += sizeof(uint64_t);
    
    // Read TTL
    uint32_t ttl = *reinterpret_cast<const uint32_t*>(buffer.get() + offset);
    offset += sizeof(uint32_t);
    
    // Check if expired
    auto now = std::chrono::system_clock::now();
    auto current_timestamp = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
    if (current_timestamp > timestamp + ttl) {
        return std::nullopt; // Expired
    }
    
    // Read and verify key
    std::string key(reinterpret_cast<const char*>(buffer.get() + offset), key_len);
    if (key != expected_key) {
        return std::nullopt; // Key mismatch
    }
    offset += key_len;
    
    // Read value
    std::string value(reinterpret_cast<const char*>(buffer.get() + offset), value_len);
    
    return value;
}

void OptimizedSSDStorage::submit_io_request(std::shared_ptr<IORequest> request) {
    {
        std::unique_lock<std::mutex> lock(pending_requests_mutex_);
        pending_requests_[request->id] = request;
    }
    
    // Add to work queue
    {
        std::unique_lock<std::mutex> lock(work_queue_mutex_);
        work_queue_.push(request);
    }
    work_queue_cv_.notify_one();
}

void OptimizedSSDStorage::io_worker() {
    while (running_) {
        std::shared_ptr<IORequest> request;
        
        // Get work from queue
        {
            std::unique_lock<std::mutex> lock(work_queue_mutex_);
            work_queue_cv_.wait(lock, [this] { return !work_queue_.empty() || !running_; });
            
            if (!running_) break;
            
            request = work_queue_.front();
            work_queue_.pop();
        }
        
        // Process request
        process_io_request(request);
    }
}

void OptimizedSSDStorage::process_io_request(std::shared_ptr<IORequest> request) {
    try {
        if (request->type == IOType::READ) {
            process_read_request(request);
        } else if (request->type == IOType::WRITE) {
            process_write_request(request);
        }
    } catch (const std::exception& e) {
        error_count_++;
        request->completion->set_value(std::nullopt);
    }
    
    // Remove from pending requests
    {
        std::unique_lock<std::mutex> lock(pending_requests_mutex_);
        pending_requests_.erase(request->id);
    }
}

void OptimizedSSDStorage::process_read_request(std::shared_ptr<IORequest> request) {
    ssize_t bytes_read = pread(request->fd, request->buffer.get(), page_size_, request->offset);
    
    if (bytes_read <= 0) {
        request->completion->set_value(std::nullopt);
        return;
    }
    
    read_count_++;
    bytes_read_ += bytes_read;
    
    auto result = parse_read_data(request->buffer, request->key);
    request->completion->set_value(result);
}

void OptimizedSSDStorage::process_write_request(std::shared_ptr<IORequest> request) {
    ssize_t bytes_written = pwrite(request->fd, request->buffer.get(), page_size_, request->offset);
    
    if (bytes_written <= 0) {
        request->completion->set_value(std::nullopt);
        return;
    }
    
    write_count_++;
    bytes_written_ += bytes_written;
    
    request->completion->set_value(std::string("OK"));
}

} // namespace storage
} // namespace meteor 