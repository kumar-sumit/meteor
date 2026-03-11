#pragma once

#include <memory>
#include <string>
#include <vector>
#include <functional>
#include <atomic>
#include <mutex>
#include <thread>
#include <sys/epoll.h>
#include <netinet/in.h>
#include "../protocol/resp_parser.hpp"

namespace garuda::network {

class DragonflyConnection {
public:
    explicit DragonflyConnection(int socket_fd);
    ~DragonflyConnection();
    
    // Non-copyable, non-movable
    DragonflyConnection(const DragonflyConnection&) = delete;
    DragonflyConnection& operator=(const DragonflyConnection&) = delete;
    DragonflyConnection(DragonflyConnection&&) = delete;
    DragonflyConnection& operator=(DragonflyConnection&&) = delete;
    
    // Handle incoming data and process commands
    bool ProcessData();
    
    // Send response back to client
    bool SendResponse(const protocol::RespValue& response);
    
    // Check if connection is still alive
    bool IsAlive() const { return alive_.load(); }
    
    // Get socket file descriptor
    int GetSocketFd() const { return socket_fd_; }
    
    // Set command handler
    using CommandHandler = std::function<protocol::RespValue(const protocol::RespValue&)>;
    void SetCommandHandler(CommandHandler handler) { command_handler_ = std::move(handler); }
    
private:
    bool ReadData();
    bool WriteData();
    void ProcessCommands();
    void HandleCommand(const protocol::RespValue& command);
    void Close();
    
    int socket_fd_;
    std::atomic<bool> alive_{true};
    
    // Buffers
    std::vector<char> read_buffer_;
    std::vector<char> write_buffer_;
    size_t read_pos_ = 0;
    size_t write_pos_ = 0;
    
    // RESP parser
    std::unique_ptr<protocol::RespParser> parser_;
    
    // Command handler
    CommandHandler command_handler_;
    
    // Thread safety for write operations
    std::mutex write_mutex_;
    
    static constexpr size_t kBufferSize = 32768; // 32KB buffer
};

class DragonflyServer {
public:
    explicit DragonflyServer(int port = 6379);
    ~DragonflyServer();
    
    // Start the server
    bool Start();
    
    // Stop the server
    void Stop();
    
    // Set command handler for all connections
    void SetCommandHandler(DragonflyConnection::CommandHandler handler);
    
    // Get server statistics
    struct Stats {
        std::atomic<uint64_t> total_connections{0};
        std::atomic<uint64_t> active_connections{0};
        std::atomic<uint64_t> total_commands{0};
        std::atomic<uint64_t> total_errors{0};
    };
    
    const Stats& GetStats() const { return stats_; }
    
private:
    void AcceptLoop();
    void WorkerLoop();
    bool SetupServerSocket();
    void HandleConnection(std::shared_ptr<DragonflyConnection> conn);
    
    int port_;
    int server_fd_ = -1;
    int epoll_fd_ = -1;
    
    std::atomic<bool> running_{false};
    std::thread accept_thread_;
    std::vector<std::thread> worker_threads_;
    
    DragonflyConnection::CommandHandler command_handler_;
    Stats stats_;
    
    std::mutex connections_mutex_;
    std::vector<std::shared_ptr<DragonflyConnection>> connections_;
    
    static constexpr int kMaxEvents = 1024;
    static constexpr int kWorkerThreads = 4;
};

} // namespace garuda::network