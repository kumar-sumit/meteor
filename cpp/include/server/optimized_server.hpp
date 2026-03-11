#pragma once

#include "../cache/sharded_cache.hpp"
#include "../io/zero_copy_io.hpp"
#include "../utils/fiber_pool.hpp"
#include "../utils/simd_utils.hpp"
#include "../protocol/resp_parser.hpp"
#include <memory>
#include <vector>
#include <atomic>
#include <thread>
#include <chrono>
#include <unordered_map>

namespace meteor {
namespace server {

// Forward declarations
class OptimizedServer;
class ConnectionContext;
class CommandProcessor;

// Server configuration for optimized implementation
struct OptimizedServerConfig {
    std::string host = "localhost";
    uint16_t port = 6379;
    
    // Performance settings
    size_t io_threads = 0;              // 0 = auto-detect
    size_t worker_fibers = 0;           // 0 = auto-detect
    size_t max_connections = 100000;
    size_t max_pipeline_size = 1000;
    
    // Buffer settings
    size_t read_buffer_size = 64 * 1024;
    size_t write_buffer_size = 64 * 1024;
    size_t max_request_size = 512 * 1024 * 1024;
    
    // Cache settings
    size_t cache_shards = 0;            // 0 = auto-detect
    size_t max_memory = 256 * 1024 * 1024;
    size_t max_entries = 1000000;
    
    // Optimization flags
    bool enable_zero_copy = true;
    bool enable_simd = true;
    bool enable_pipeline_batching = true;
    bool enable_fiber_scheduling = true;
    bool enable_numa_awareness = true;
    
    // Monitoring
    bool enable_metrics = true;
    std::chrono::seconds metrics_interval = std::chrono::seconds(10);
    
    // Logging
    bool enable_logging = false;
    enum class LogLevel {
        DEBUG, INFO, WARN, ERROR
    } log_level = LogLevel::INFO;
};

// Per-connection context with optimizations
class ConnectionContext {
public:
    explicit ConnectionContext(std::unique_ptr<io::ZeroCopyConnection> connection, 
                              cache::ShardedCache* cache,
                              OptimizedServerConfig* config);
    ~ConnectionContext();
    
    // Non-copyable, movable
    ConnectionContext(const ConnectionContext&) = delete;
    ConnectionContext& operator=(const ConnectionContext&) = delete;
    ConnectionContext(ConnectionContext&&) = default;
    ConnectionContext& operator=(ConnectionContext&&) = default;
    
    // Connection management
    void start();
    void close();
    bool is_active() const;
    
    // Request processing
    void process_requests();
    
    // Statistics
    uint64_t get_requests_processed() const { return requests_processed_.load(std::memory_order_relaxed); }
    uint64_t get_bytes_read() const { return bytes_read_.load(std::memory_order_relaxed); }
    uint64_t get_bytes_written() const { return bytes_written_.load(std::memory_order_relaxed); }
    
private:
    std::unique_ptr<io::ZeroCopyConnection> connection_;
    cache::ShardedCache* cache_;
    OptimizedServerConfig* config_;
    
    // Request parsing and batching
    std::unique_ptr<protocol::RESPParser> parser_;
    std::vector<protocol::RESPValue> pending_requests_;
    std::vector<std::string> pending_responses_;
    
    // Buffers
    std::unique_ptr<io::IOBuffer> read_buffer_;
    std::unique_ptr<io::IOBuffer> write_buffer_;
    
    // Statistics
    std::atomic<uint64_t> requests_processed_{0};
    std::atomic<uint64_t> bytes_read_{0};
    std::atomic<uint64_t> bytes_written_{0};
    
    // Pipeline processing
    void process_pipeline_batch();
    void execute_command(const protocol::RESPValue& command, std::string& response);
    
    // I/O callbacks
    void on_read_complete(int result, std::unique_ptr<io::IOBuffer> buffer);
    void on_write_complete(int result, std::unique_ptr<io::IOBuffer> buffer);
    
    // SIMD-optimized response generation
    void generate_bulk_response(const std::string& value, std::string& response);
    void generate_error_response(const std::string& error, std::string& response);
    void generate_ok_response(std::string& response);
    void generate_null_response(std::string& response);
};

// High-performance command processor with batching
class CommandProcessor {
public:
    explicit CommandProcessor(cache::ShardedCache* cache, OptimizedServerConfig* config);
    ~CommandProcessor() = default;
    
    // Non-copyable, non-movable
    CommandProcessor(const CommandProcessor&) = delete;
    CommandProcessor& operator=(const CommandProcessor&) = delete;
    CommandProcessor(CommandProcessor&&) = delete;
    CommandProcessor& operator=(CommandProcessor&&) = delete;
    
    // Command execution
    void execute_command(const protocol::RESPValue& command, std::string& response);
    
    // Batch processing for pipelines
    void execute_batch(const std::vector<protocol::RESPValue>& commands, 
                      std::vector<std::string>& responses);
    
    // Statistics
    uint64_t get_commands_executed() const { return commands_executed_.load(std::memory_order_relaxed); }
    uint64_t get_batch_operations() const { return batch_operations_.load(std::memory_order_relaxed); }
    
private:
    cache::ShardedCache* cache_;
    OptimizedServerConfig* config_;
    
    // Command handlers
    void handle_get(const protocol::RESPValue& command, std::string& response);
    void handle_set(const protocol::RESPValue& command, std::string& response);
    void handle_del(const protocol::RESPValue& command, std::string& response);
    void handle_exists(const protocol::RESPValue& command, std::string& response);
    void handle_ping(const protocol::RESPValue& command, std::string& response);
    void handle_info(const protocol::RESPValue& command, std::string& response);
    void handle_flushall(const protocol::RESPValue& command, std::string& response);
    
    // Batch optimized handlers
    void handle_mget(const protocol::RESPValue& command, std::string& response);
    void handle_mset(const protocol::RESPValue& command, std::string& response);
    void handle_mdel(const protocol::RESPValue& command, std::string& response);
    
    // Statistics
    std::atomic<uint64_t> commands_executed_{0};
    std::atomic<uint64_t> batch_operations_{0};
    
    // Command dispatch table
    using CommandHandler = void (CommandProcessor::*)(const protocol::RESPValue&, std::string&);
    std::unordered_map<std::string, CommandHandler> command_handlers_;
    
    // SIMD-optimized command matching
    CommandHandler find_command_handler(const std::string& command);
    
    // Response generation helpers
    void generate_response(const std::string& value, std::string& response);
    void generate_array_response(const std::vector<std::string>& values, std::string& response);
    void generate_integer_response(int64_t value, std::string& response);
};

// Server metrics and monitoring
struct ServerMetrics {
    std::atomic<uint64_t> total_connections{0};
    std::atomic<uint64_t> active_connections{0};
    std::atomic<uint64_t> total_requests{0};
    std::atomic<uint64_t> total_responses{0};
    std::atomic<uint64_t> total_errors{0};
    std::atomic<uint64_t> bytes_read{0};
    std::atomic<uint64_t> bytes_written{0};
    
    // Performance metrics
    std::atomic<uint64_t> pipeline_batches{0};
    std::atomic<uint64_t> fiber_yields{0};
    std::atomic<uint64_t> cache_hits{0};
    std::atomic<uint64_t> cache_misses{0};
    
    // Timing metrics
    std::atomic<uint64_t> total_request_time_ns{0};
    std::atomic<uint64_t> min_request_time_ns{UINT64_MAX};
    std::atomic<uint64_t> max_request_time_ns{0};
    
    std::chrono::steady_clock::time_point start_time;
    
    ServerMetrics() : start_time(std::chrono::steady_clock::now()) {}
    
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
    
    double get_cache_hit_rate() const {
        auto hits = cache_hits.load();
        auto misses = cache_misses.load();
        return hits + misses > 0 ? static_cast<double>(hits) / (hits + misses) : 0.0;
    }
};

// Ultra-high-performance Redis-compatible server
class OptimizedServer {
public:
    explicit OptimizedServer(const OptimizedServerConfig& config);
    ~OptimizedServer();
    
    // Non-copyable, non-movable
    OptimizedServer(const OptimizedServer&) = delete;
    OptimizedServer& operator=(const OptimizedServer&) = delete;
    OptimizedServer(OptimizedServer&&) = delete;
    OptimizedServer& operator=(OptimizedServer&&) = delete;
    
    // Server lifecycle
    bool start();
    void stop();
    bool is_running() const { return running_.load(std::memory_order_acquire); }
    
    // Configuration
    const OptimizedServerConfig& get_config() const { return config_; }
    
    // Metrics
    const ServerMetrics& get_metrics() const { return metrics_; }
    void reset_metrics() { metrics_ = ServerMetrics(); }
    
    // Cache access
    cache::ShardedCache* get_cache() { return cache_.get(); }
    
private:
    OptimizedServerConfig config_;
    std::atomic<bool> running_{false};
    
    // Core components
    std::unique_ptr<cache::ShardedCache> cache_;
    std::unique_ptr<io::ZeroCopyServer> io_server_;
    std::unique_ptr<utils::FiberPool> fiber_pool_;
    std::unique_ptr<CommandProcessor> command_processor_;
    
    // Connection management
    std::vector<std::unique_ptr<ConnectionContext>> connections_;
    std::mutex connections_mutex_;
    
    // Metrics and monitoring
    ServerMetrics metrics_;
    std::thread metrics_thread_;
    
    // Initialization
    bool initialize_cache();
    bool initialize_io_system();
    bool initialize_fiber_pool();
    bool initialize_command_processor();
    
    // Connection handling
    void on_new_connection(std::unique_ptr<io::ZeroCopyConnection> connection);
    void cleanup_connections();
    
    // Metrics collection
    void metrics_loop();
    void collect_metrics();
    void print_metrics();
    
    // NUMA optimization
    void optimize_numa_affinity();
    
    // Logging
    void log(OptimizedServerConfig::LogLevel level, const std::string& message);
};

} // namespace server
} // namespace meteor 