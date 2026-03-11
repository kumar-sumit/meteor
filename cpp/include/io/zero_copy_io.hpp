#pragma once

#include <memory>
#include <vector>
#include <queue>
#include <functional>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <sys/socket.h>
#include <netinet/in.h>

#ifdef __linux__
#include <liburing.h>
#endif

#ifdef __APPLE__
#include <sys/event.h>
#endif

namespace meteor {
namespace io {

// Forward declarations
class ZeroCopyIOManager;
class IOBuffer;
class IOContext;

// Zero-copy buffer management
class IOBuffer {
public:
    explicit IOBuffer(size_t size);
    ~IOBuffer();
    
    // Non-copyable, movable
    IOBuffer(const IOBuffer&) = delete;
    IOBuffer& operator=(const IOBuffer&) = delete;
    IOBuffer(IOBuffer&&) = default;
    IOBuffer& operator=(IOBuffer&&) = default;
    
    // Buffer access
    char* data() { return data_; }
    const char* data() const { return data_; }
    size_t size() const { return size_; }
    size_t capacity() const { return capacity_; }
    
    // Buffer operations
    void resize(size_t new_size);
    void clear() { size_ = 0; }
    void append(const char* data, size_t len);
    void consume(size_t len);
    
    // Zero-copy operations
    void* get_iovec_base() { return data_; }
    size_t get_iovec_len() const { return size_; }
    
private:
    char* data_;
    size_t size_;
    size_t capacity_;
    bool is_aligned_;
    
    // Ensure proper alignment for DMA
    static constexpr size_t ALIGNMENT = 4096;
    void* allocate_aligned(size_t size);
    void deallocate_aligned(void* ptr);
};

// I/O operation types
enum class IOOperation {
    READ,
    WRITE,
    ACCEPT,
    CONNECT,
    CLOSE
};

// I/O completion callback
using IOCallback = std::function<void(int result, std::unique_ptr<IOBuffer> buffer)>;

// I/O request context
struct IORequest {
    IOOperation operation;
    int fd;
    std::unique_ptr<IOBuffer> buffer;
    IOCallback callback;
    sockaddr_in addr;
    socklen_t addr_len;
    uint64_t user_data;
    
    IORequest(IOOperation op, int socket_fd, std::unique_ptr<IOBuffer> buf, IOCallback cb)
        : operation(op), fd(socket_fd), buffer(std::move(buf)), callback(std::move(cb)), addr_len(sizeof(addr)) {}
};

// Platform-specific I/O backend
class IOBackend {
public:
    virtual ~IOBackend() = default;
    
    // Lifecycle
    virtual bool initialize() = 0;
    virtual void shutdown() = 0;
    
    // I/O operations
    virtual bool submit_read(int fd, std::unique_ptr<IOBuffer> buffer, IOCallback callback) = 0;
    virtual bool submit_write(int fd, std::unique_ptr<IOBuffer> buffer, IOCallback callback) = 0;
    virtual bool submit_accept(int fd, IOCallback callback) = 0;
    virtual bool submit_connect(int fd, const sockaddr_in& addr, IOCallback callback) = 0;
    virtual bool submit_close(int fd, IOCallback callback) = 0;
    
    // Event processing
    virtual size_t process_events(std::chrono::milliseconds timeout) = 0;
    
    // Statistics
    virtual size_t get_pending_operations() const = 0;
    virtual size_t get_completed_operations() const = 0;
};

#ifdef __linux__
// Linux io_uring backend
class IOUringBackend : public IOBackend {
public:
    explicit IOUringBackend(size_t queue_depth = 1024);
    ~IOUringBackend() override;
    
    // IOBackend interface
    bool initialize() override;
    void shutdown() override;
    
    bool submit_read(int fd, std::unique_ptr<IOBuffer> buffer, IOCallback callback) override;
    bool submit_write(int fd, std::unique_ptr<IOBuffer> buffer, IOCallback callback) override;
    bool submit_accept(int fd, IOCallback callback) override;
    bool submit_connect(int fd, const sockaddr_in& addr, IOCallback callback) override;
    bool submit_close(int fd, IOCallback callback) override;
    
    size_t process_events(std::chrono::milliseconds timeout) override;
    
    size_t get_pending_operations() const override { return pending_ops_.load(std::memory_order_acquire); }
    size_t get_completed_operations() const override { return completed_ops_.load(std::memory_order_acquire); }
    
private:
    struct io_uring ring_;
    size_t queue_depth_;
    std::atomic<size_t> pending_ops_{0};
    std::atomic<size_t> completed_ops_{0};
    
    // Request tracking
    std::unordered_map<uint64_t, std::unique_ptr<IORequest>> active_requests_;
    std::atomic<uint64_t> next_request_id_{1};
    std::mutex requests_mutex_;
    
    // Helper methods
    bool submit_request(std::unique_ptr<IORequest> request);
    void complete_request(struct io_uring_cqe* cqe);
};
#endif

#ifdef __APPLE__
// macOS kqueue backend
class KQueueBackend : public IOBackend {
public:
    explicit KQueueBackend(size_t max_events = 1024);
    ~KQueueBackend() override;
    
    // IOBackend interface
    bool initialize() override;
    void shutdown() override;
    
    bool submit_read(int fd, std::unique_ptr<IOBuffer> buffer, IOCallback callback) override;
    bool submit_write(int fd, std::unique_ptr<IOBuffer> buffer, IOCallback callback) override;
    bool submit_accept(int fd, IOCallback callback) override;
    bool submit_connect(int fd, const sockaddr_in& addr, IOCallback callback) override;
    bool submit_close(int fd, IOCallback callback) override;
    
    size_t process_events(std::chrono::milliseconds timeout) override;
    
    size_t get_pending_operations() const override { return pending_ops_.load(std::memory_order_acquire); }
    size_t get_completed_operations() const override { return completed_ops_.load(std::memory_order_acquire); }
    
private:
    int kqueue_fd_;
    size_t max_events_;
    std::vector<struct kevent> events_;
    std::atomic<size_t> pending_ops_{0};
    std::atomic<size_t> completed_ops_{0};
    
    // Request tracking
    std::unordered_map<int, std::unique_ptr<IORequest>> active_requests_;
    std::mutex requests_mutex_;
    
    // Helper methods
    bool submit_kevent(int fd, int16_t filter, uint16_t flags, void* udata);
    void process_kevent(const struct kevent& event);
};
#endif

// High-level zero-copy I/O manager
class ZeroCopyIOManager {
public:
    explicit ZeroCopyIOManager(size_t num_threads = 0);
    ~ZeroCopyIOManager();
    
    // Non-copyable, non-movable
    ZeroCopyIOManager(const ZeroCopyIOManager&) = delete;
    ZeroCopyIOManager& operator=(const ZeroCopyIOManager&) = delete;
    ZeroCopyIOManager(ZeroCopyIOManager&&) = delete;
    ZeroCopyIOManager& operator=(ZeroCopyIOManager&&) = delete;
    
    // Lifecycle
    bool start();
    void stop();
    bool is_running() const { return running_.load(std::memory_order_acquire); }
    
    // I/O operations
    bool async_read(int fd, size_t buffer_size, IOCallback callback);
    bool async_write(int fd, std::unique_ptr<IOBuffer> buffer, IOCallback callback);
    bool async_accept(int fd, IOCallback callback);
    bool async_connect(int fd, const sockaddr_in& addr, IOCallback callback);
    bool async_close(int fd, IOCallback callback);
    
    // Buffer management
    std::unique_ptr<IOBuffer> allocate_buffer(size_t size);
    void return_buffer(std::unique_ptr<IOBuffer> buffer);
    
    // Statistics
    size_t get_total_pending_operations() const;
    size_t get_total_completed_operations() const;
    size_t get_buffer_pool_size() const { return buffer_pool_.size(); }
    
private:
    // I/O threads
    struct IOThread {
        std::thread thread;
        std::unique_ptr<IOBackend> backend;
        std::atomic<bool> should_stop{false};
        size_t thread_id;
        
        explicit IOThread(size_t id) : thread_id(id) {}
    };
    
    std::vector<std::unique_ptr<IOThread>> io_threads_;
    std::atomic<bool> running_{false};
    std::atomic<size_t> next_thread_{0};
    
    // Buffer pool
    std::queue<std::unique_ptr<IOBuffer>> buffer_pool_;
    std::mutex buffer_pool_mutex_;
    
    // Thread management
    void io_thread_loop(IOThread* thread);
    size_t get_next_thread();
    
    // Platform-specific backend creation
    std::unique_ptr<IOBackend> create_backend();
};

// Connection handler with zero-copy I/O
class ZeroCopyConnection {
public:
    explicit ZeroCopyConnection(int fd, ZeroCopyIOManager* io_manager);
    ~ZeroCopyConnection();
    
    // Non-copyable, movable
    ZeroCopyConnection(const ZeroCopyConnection&) = delete;
    ZeroCopyConnection& operator=(const ZeroCopyConnection&) = delete;
    ZeroCopyConnection(ZeroCopyConnection&&) = default;
    ZeroCopyConnection& operator=(ZeroCopyConnection&&) = default;
    
    // Connection management
    void start();
    void close();
    bool is_active() const { return active_.load(std::memory_order_acquire); }
    
    // I/O operations
    void async_read(IOCallback callback);
    void async_write(std::unique_ptr<IOBuffer> buffer, IOCallback callback);
    
    // Connection info
    int get_fd() const { return fd_; }
    const sockaddr_in& get_peer_addr() const { return peer_addr_; }
    
    // Statistics
    size_t get_bytes_read() const { return bytes_read_.load(std::memory_order_acquire); }
    size_t get_bytes_written() const { return bytes_written_.load(std::memory_order_acquire); }
    
private:
    int fd_;
    ZeroCopyIOManager* io_manager_;
    sockaddr_in peer_addr_;
    std::atomic<bool> active_{false};
    
    // Statistics
    std::atomic<size_t> bytes_read_{0};
    std::atomic<size_t> bytes_written_{0};
    
    // I/O callbacks
    void on_read_complete(int result, std::unique_ptr<IOBuffer> buffer);
    void on_write_complete(int result, std::unique_ptr<IOBuffer> buffer);
};

// Zero-copy server with high-performance accept loop
class ZeroCopyServer {
public:
    explicit ZeroCopyServer(const std::string& host, uint16_t port, size_t io_threads = 0);
    ~ZeroCopyServer();
    
    // Non-copyable, non-movable
    ZeroCopyServer(const ZeroCopyServer&) = delete;
    ZeroCopyServer& operator=(const ZeroCopyServer&) = delete;
    ZeroCopyServer(ZeroCopyServer&&) = delete;
    ZeroCopyServer& operator=(ZeroCopyServer&&) = delete;
    
    // Server lifecycle
    bool start();
    void stop();
    bool is_running() const { return running_.load(std::memory_order_acquire); }
    
    // Connection callback
    using ConnectionCallback = std::function<void(std::unique_ptr<ZeroCopyConnection>)>;
    void set_connection_callback(ConnectionCallback callback) { connection_callback_ = std::move(callback); }
    
    // Server statistics
    size_t get_active_connections() const { return active_connections_.load(std::memory_order_acquire); }
    size_t get_total_connections() const { return total_connections_.load(std::memory_order_acquire); }
    
private:
    std::string host_;
    uint16_t port_;
    int listen_fd_;
    std::unique_ptr<ZeroCopyIOManager> io_manager_;
    std::atomic<bool> running_{false};
    
    // Connection management
    ConnectionCallback connection_callback_;
    std::atomic<size_t> active_connections_{0};
    std::atomic<size_t> total_connections_{0};
    
    // Accept loop
    void start_accept();
    void on_accept_complete(int result, std::unique_ptr<IOBuffer> buffer);
    
    // Socket setup
    bool setup_listen_socket();
    void configure_socket(int fd);
};

} // namespace io
} // namespace meteor 