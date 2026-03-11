#pragma once

#include "../cache/cache.hpp"
#include "../protocol/resp_parser.hpp"
#include "../utils/thread_pool.hpp"
#include <memory>
#include <string>
#include <atomic>
#include <chrono>
#include <functional>
#include <unordered_map>
#include <thread>
#include <mutex>
#include <condition_variable>

namespace meteor {
namespace server {

// Forward declarations
class ConnectionHandler;
class CommandRegistry;

// Server configuration
struct ServerConfig {
    std::string host = "localhost";
    uint16_t port = 6379;
    
    // Connection settings
    size_t max_connections = 10000;
    size_t backlog = 1024;
    std::chrono::milliseconds read_timeout = std::chrono::seconds(30);
    std::chrono::milliseconds write_timeout = std::chrono::seconds(30);
    std::chrono::milliseconds idle_timeout = std::chrono::minutes(5);
    
    // Buffer settings
    size_t read_buffer_size = 64 * 1024;
    size_t write_buffer_size = 64 * 1024;
    size_t max_request_size = 512 * 1024 * 1024; // 512MB
    
    // Threading
    size_t worker_threads = 0; // 0 = auto-detect
    size_t io_threads = 0; // 0 = auto-detect
    
    // Performance
    bool enable_tcp_nodelay = true;
    bool enable_tcp_keepalive = true;
    bool enable_so_reuseport = true;
    int tcp_keepalive_idle = 300;
    int tcp_keepalive_interval = 60;
    int tcp_keepalive_count = 3;
    
    // Logging
    bool enable_logging = false;
    enum class LogLevel {
        DEBUG,
        INFO,
        WARN,
        ERROR
    } log_level = LogLevel::INFO;
};

// Connection statistics
struct ConnectionStats {
    std::atomic<uint64_t> total_connections{0};
    std::atomic<uint64_t> active_connections{0};
    std::atomic<uint64_t> total_requests{0};
    std::atomic<uint64_t> total_responses{0};
    std::atomic<uint64_t> total_errors{0};
    std::atomic<uint64_t> bytes_read{0};
    std::atomic<uint64_t> bytes_written{0};
    
    // Timing statistics
    std::atomic<uint64_t> total_request_time_ns{0};
    std::atomic<uint64_t> min_request_time_ns{UINT64_MAX};
    std::atomic<uint64_t> max_request_time_ns{0};
    
    // Connection lifecycle
    std::chrono::steady_clock::time_point start_time;
    
    ConnectionStats() : start_time(std::chrono::steady_clock::now()) {}
    
    double get_requests_per_second() const {
        auto now = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::seconds>(now - start_time);
        return duration.count() > 0 ? 
               static_cast<double>(total_requests.load()) / duration.count() : 0.0;
    }
    
    double get_average_request_time_ms() const {
        auto total_requests_val = total_requests.load();
        return total_requests_val > 0 ? 
               static_cast<double>(total_request_time_ns.load()) / 
               (total_requests_val * 1000000.0) : 0.0;
    }
};

// High-performance TCP server
class TCPServer {
public:
    explicit TCPServer(const ServerConfig& config, 
                      std::shared_ptr<cache::Cache> cache);
    ~TCPServer();
    
    // Non-copyable, non-movable
    TCPServer(const TCPServer&) = delete;
    TCPServer& operator=(const TCPServer&) = delete;
    TCPServer(TCPServer&&) = delete;
    TCPServer& operator=(TCPServer&&) = delete;
    
    // Server lifecycle
    bool start();
    void stop();
    bool is_running() const { return running_.load(); }
    
    // Statistics
    const ConnectionStats& get_stats() const { return stats_; }
    void reset_stats();
    
    // Configuration
    const ServerConfig& get_config() const { return config_; }
    void set_cache(std::shared_ptr<cache::Cache> cache) { cache_ = cache; }

private:
    // Configuration and state
    ServerConfig config_;
    std::shared_ptr<cache::Cache> cache_;
    std::atomic<bool> running_{false};
    
    // Network
    int server_socket_ = -1;
    
    // Threading
    std::unique_ptr<utils::ThreadPool> worker_pool_;
    std::unique_ptr<utils::ThreadPool> io_pool_;
    std::thread accept_thread_;
    
    // Connection management
    std::unordered_map<int, std::unique_ptr<ConnectionHandler>> connections_;
    std::mutex connections_mutex_;
    
    // Command processing
    std::unique_ptr<CommandRegistry> command_registry_;
    
    // Statistics
    ConnectionStats stats_;
    
    // Internal methods
    bool setup_server_socket();
    void configure_socket(int socket_fd);
    void accept_loop();
    void handle_new_connection(int client_socket);
    void cleanup_connection(int client_socket);
    
    // Utility methods
    void log(ServerConfig::LogLevel level, const std::string& message);
    std::string format_address(const std::string& host, uint16_t port) const;
    
    // Constants
    static constexpr int INVALID_SOCKET = -1;
    static constexpr int SOCKET_ERROR = -1;
};

// Connection handler for individual client connections
class ConnectionHandler {
public:
    ConnectionHandler(int socket_fd, 
                     std::shared_ptr<cache::Cache> cache,
                     std::shared_ptr<CommandRegistry> registry,
                     const ServerConfig& config);
    ~ConnectionHandler();
    
    // Non-copyable, non-movable
    ConnectionHandler(const ConnectionHandler&) = delete;
    ConnectionHandler& operator=(const ConnectionHandler&) = delete;
    ConnectionHandler(ConnectionHandler&&) = delete;
    ConnectionHandler& operator=(ConnectionHandler&&) = delete;
    
    // Connection lifecycle
    void start();
    void stop();
    bool is_active() const { return active_.load(); }
    
    // Connection info
    int get_socket() const { return socket_fd_; }
    std::string get_remote_address() const { return remote_address_; }
    
    // Statistics
    uint64_t get_requests_processed() const { return requests_processed_; }
    uint64_t get_bytes_read() const { return bytes_read_; }
    uint64_t get_bytes_written() const { return bytes_written_; }

private:
    // Configuration
    int socket_fd_;
    std::shared_ptr<cache::Cache> cache_;
    std::shared_ptr<CommandRegistry> registry_;
    ServerConfig config_;
    
    // State
    std::atomic<bool> active_{false};
    std::string remote_address_;
    
    // Protocol handling
    std::unique_ptr<protocol::RESPParser> parser_;
    std::unique_ptr<protocol::RESPSerializer> serializer_;
    
    // Buffers
    std::vector<char> read_buffer_;
    std::vector<char> write_buffer_;
    size_t read_pos_ = 0;
    size_t write_pos_ = 0;
    
    // Statistics
    std::atomic<uint64_t> requests_processed_{0};
    std::atomic<uint64_t> bytes_read_{0};
    std::atomic<uint64_t> bytes_written_{0};
    std::chrono::steady_clock::time_point last_activity_;
    
    // Internal methods
    void process_loop();
    bool read_data();
    bool write_data();
    bool process_requests();
    bool handle_command(const protocol::RESPValue& command);
    
    // Utility methods
    bool is_socket_ready_for_read() const;
    bool is_socket_ready_for_write() const;
    void update_last_activity();
    bool is_connection_timed_out() const;
    std::string get_socket_address(int socket_fd) const;
    
    // Constants
    static constexpr size_t MIN_READ_SIZE = 1024;
    static constexpr size_t MAX_WRITE_BATCH = 64 * 1024;
};

// Command registry for Redis commands
class CommandRegistry {
public:
    using CommandHandler = std::function<protocol::RESPValue(
        const std::vector<std::string>&, 
        std::shared_ptr<cache::Cache>)>;
    
    CommandRegistry();
    ~CommandRegistry() = default;
    
    // Command registration
    void register_command(const std::string& name, CommandHandler handler);
    void unregister_command(const std::string& name);
    
    // Command execution
    protocol::RESPValue execute_command(const std::string& name,
                                       const std::vector<std::string>& args,
                                       std::shared_ptr<cache::Cache> cache);
    
    // Command info
    bool has_command(const std::string& name) const;
    std::vector<std::string> get_command_names() const;
    
    // Statistics
    uint64_t get_command_count(const std::string& name) const;
    std::unordered_map<std::string, uint64_t> get_all_command_counts() const;
    void reset_stats();

private:
    std::unordered_map<std::string, CommandHandler> commands_;
    mutable std::shared_mutex commands_mutex_;
    
    // Statistics
    std::unordered_map<std::string, std::atomic<uint64_t>> command_stats_;
    mutable std::shared_mutex stats_mutex_;
    
    // Built-in commands
    void register_builtin_commands();
    
    // Command implementations
    static protocol::RESPValue cmd_ping(const std::vector<std::string>& args,
                                       std::shared_ptr<cache::Cache> cache);
    static protocol::RESPValue cmd_get(const std::vector<std::string>& args,
                                      std::shared_ptr<cache::Cache> cache);
    static protocol::RESPValue cmd_set(const std::vector<std::string>& args,
                                      std::shared_ptr<cache::Cache> cache);
    static protocol::RESPValue cmd_del(const std::vector<std::string>& args,
                                      std::shared_ptr<cache::Cache> cache);
    static protocol::RESPValue cmd_exists(const std::vector<std::string>& args,
                                         std::shared_ptr<cache::Cache> cache);
    static protocol::RESPValue cmd_flushall(const std::vector<std::string>& args,
                                           std::shared_ptr<cache::Cache> cache);
    static protocol::RESPValue cmd_info(const std::vector<std::string>& args,
                                       std::shared_ptr<cache::Cache> cache);
    static protocol::RESPValue cmd_quit(const std::vector<std::string>& args,
                                       std::shared_ptr<cache::Cache> cache);
    
    // Utility methods
    static std::string normalize_command_name(const std::string& name);
    static protocol::RESPValue create_error(const std::string& message);
    static protocol::RESPValue create_ok();
    static protocol::RESPValue create_null();
};

} // namespace server
} // namespace meteor 