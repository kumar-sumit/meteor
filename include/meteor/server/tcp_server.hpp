#pragma once

#include <atomic>
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <shared_mutex>
#include <string>
#include <thread>
#include <vector>

namespace meteor {
namespace protocol {
class RESPParser;
class RESPSerializer;
struct RESPValue;
}

namespace utils {
class MemoryPool;
class ThreadPool;
}

namespace server {

struct Config {
    std::string host = "localhost";
    int port = 6379;
    size_t max_connections = 1000;
    size_t buffer_size = 65536;
    size_t memory_pool_size = 1024;
    size_t worker_threads = 8;
    int backlog = 128;
    bool enable_logging = false;
};

struct PooledConnection {
    int fd = -1;
    std::unique_ptr<protocol::RESPParser> parser;
    std::unique_ptr<protocol::RESPSerializer> serializer;
    std::vector<char> read_buffer;
    std::string write_buffer;
    std::chrono::steady_clock::time_point last_used;
    uint64_t total_requests = 0;
    uint64_t total_bytes = 0;
};

struct ConnectionPoolStats {
    size_t pool_size;
    size_t max_size;
    uint64_t total_created;
    uint64_t total_reused;
};

class ConnectionPool {
public:
    ConnectionPool(size_t max_size, size_t buffer_size);
    ~ConnectionPool();

    // Disable copy and move
    ConnectionPool(const ConnectionPool&) = delete;
    ConnectionPool& operator=(const ConnectionPool&) = delete;
    ConnectionPool(ConnectionPool&&) = delete;
    ConnectionPool& operator=(ConnectionPool&&) = delete;

    std::unique_ptr<PooledConnection> get_connection();
    void return_connection(std::unique_ptr<PooledConnection> conn);
    void stop();
    
    ConnectionPoolStats get_stats() const;

private:
    size_t max_size_;
    size_t buffer_size_;
    std::queue<PooledConnection*> available_connections_;
    std::mutex pool_mutex_;
    std::atomic<size_t> pool_size_;
    std::atomic<uint64_t> total_created_;
    std::atomic<uint64_t> total_reused_;
    std::atomic<bool> running_;
    
    std::thread cleanup_thread_;
    mutable std::shared_mutex pool_stats_mutex_;
    
    void cleanup_worker();
    void cleanup_expired_connections();
};

struct ServerStats {
    uint64_t active_connections;
    uint64_t total_connections;
    uint64_t total_requests;
    uint64_t total_errors;
    ConnectionPoolStats pool_stats;
};

using CommandHandler = std::function<protocol::RESPValue(const protocol::RESPValue&)>;

class TCPServer {
public:
    explicit TCPServer(const Config& config);
    ~TCPServer();

    // Disable copy and move
    TCPServer(const TCPServer&) = delete;
    TCPServer& operator=(const TCPServer&) = delete;
    TCPServer(TCPServer&&) = delete;
    TCPServer& operator=(TCPServer&&) = delete;

    bool start();
    void stop();
    
    void set_command_handler(CommandHandler handler);
    ServerStats get_stats() const;

private:
    Config config_;
    int server_fd_;
    std::atomic<bool> running_;
    
    // Core components
    std::unique_ptr<utils::MemoryPool> memory_pool_;
    std::unique_ptr<utils::ThreadPool> thread_pool_;
    std::unique_ptr<ConnectionPool> connection_pool_;
    
    // Command handling
    CommandHandler command_handler_;
    
    // Threading
    std::thread accept_thread_;
    
    // Statistics
    std::atomic<uint64_t> active_connections_;
    std::atomic<uint64_t> total_connections_;
    std::atomic<uint64_t> total_requests_;
    std::atomic<uint64_t> total_errors_;
    
    // Private methods
    bool configure_socket();
    bool configure_client_socket(int client_fd);
    void accept_loop();
    void handle_connection(int client_fd, const std::string& client_ip);
};

} // namespace server
} // namespace meteor 