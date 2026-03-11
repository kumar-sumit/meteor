#pragma once

#include <memory>
#include <vector>
#include <functional>
#include <atomic>
#include <thread>

#ifdef HAVE_LIBURING
#include <liburing.h>
#endif

#include "../protocol/resp_parser.hpp"

namespace garuda::network {

// Helio-inspired io_uring implementation
class IoUringContext {
public:
    explicit IoUringContext(unsigned entries = 256);
    ~IoUringContext();
    
    // Initialize io_uring
    bool Initialize();
    
    // Submit and wait for completions
    int Submit();
    int WaitCompletion(int min_complete = 1);
    
    // Queue operations
    bool QueueAccept(int listen_fd, sockaddr* addr, socklen_t* addrlen, void* user_data);
    bool QueueRead(int fd, void* buffer, size_t size, void* user_data);
    bool QueueWrite(int fd, const void* buffer, size_t size, void* user_data);
    bool QueueClose(int fd, void* user_data);
    
    // Process completion queue
    struct CompletionEvent {
        void* user_data;
        int result;
        uint32_t flags;
    };
    
    std::vector<CompletionEvent> GetCompletions();
    
private:
#ifdef HAVE_LIBURING
    struct io_uring ring_;
    bool initialized_ = false;
#endif
    unsigned entries_;
};

// Fiber-based connection handler (Dragonfly-style)
class FiberConnection {
public:
    explicit FiberConnection(int socket_fd, IoUringContext* io_context);
    ~FiberConnection();
    
    // Fiber entry point
    void Run();
    
    // Async I/O operations
    bool AsyncRead(void* buffer, size_t size);
    bool AsyncWrite(const void* buffer, size_t size);
    
    // RESP protocol handling
    bool ProcessRespCommands();
    
    // Set command handler
    using CommandHandler = std::function<protocol::RespValue(const protocol::RespValue&)>;
    void SetCommandHandler(CommandHandler handler) { command_handler_ = std::move(handler); }
    
    // Connection state
    bool IsAlive() const { return alive_.load(); }
    int GetSocketFd() const { return socket_fd_; }
    
private:
    int socket_fd_;
    std::atomic<bool> alive_{true};
    IoUringContext* io_context_;
    
    // Buffers
    std::vector<char> read_buffer_;
    std::vector<char> write_buffer_;
    size_t read_pos_ = 0;
    size_t write_pos_ = 0;
    
    // RESP parser
    std::unique_ptr<protocol::RespParser> parser_;
    CommandHandler command_handler_;
    
    // Fiber context (simplified - real implementation would use boost::context or similar)
    void* fiber_context_ = nullptr;
    
    static constexpr size_t kBufferSize = 32768;
};

// Helio-style proactor server
class HelioProactorServer {
public:
    explicit HelioProactorServer(int port = 6379, int proactor_count = 4);
    ~HelioProactorServer();
    
    // Start/stop server
    bool Start();
    void Stop();
    
    // Set command handler
    void SetCommandHandler(FiberConnection::CommandHandler handler);
    
    // Server statistics
    struct Stats {
        std::atomic<uint64_t> total_connections{0};
        std::atomic<uint64_t> active_connections{0};
        std::atomic<uint64_t> total_commands{0};
        std::atomic<uint64_t> io_uring_submissions{0};
        std::atomic<uint64_t> io_uring_completions{0};
    };
    
    const Stats& GetStats() const { return stats_; }
    
private:
    // Proactor thread main loop
    void ProactorLoop(int proactor_id);
    
    // Setup server socket
    bool SetupServerSocket();
    
    // Handle new connections
    void HandleNewConnection(int client_fd, int proactor_id);
    
    int port_;
    int proactor_count_;
    int server_fd_ = -1;
    
    std::atomic<bool> running_{false};
    std::vector<std::thread> proactor_threads_;
    std::vector<std::unique_ptr<IoUringContext>> io_contexts_;
    
    FiberConnection::CommandHandler command_handler_;
    Stats stats_;
    
    // Connection management per proactor
    std::vector<std::vector<std::unique_ptr<FiberConnection>>> proactor_connections_;
};

} // namespace garuda::network