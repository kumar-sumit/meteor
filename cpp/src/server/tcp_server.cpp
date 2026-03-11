#include "../../include/server/tcp_server.hpp"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <iostream>
#include <cstring>

namespace meteor {
namespace server {

TCPServer::TCPServer(const ServerConfig& config, std::shared_ptr<cache::Cache> cache)
    : config_(config), cache_(cache) {
    
    // Initialize thread pools
    size_t worker_threads = config_.worker_threads > 0 ? 
                           config_.worker_threads : std::thread::hardware_concurrency();
    size_t io_threads = config_.io_threads > 0 ? 
                       config_.io_threads : std::max(2U, std::thread::hardware_concurrency() / 2);
    
    worker_pool_ = std::make_unique<utils::ThreadPool>(worker_threads);
    io_pool_ = std::make_unique<utils::ThreadPool>(io_threads);
    
    // Initialize command registry
    command_registry_ = std::make_unique<CommandRegistry>();
    
    if (config_.enable_logging) {
        log(ServerConfig::LogLevel::INFO, "TCP Server initialized with " + 
            std::to_string(worker_threads) + " worker threads and " + 
            std::to_string(io_threads) + " I/O threads");
    }
}

TCPServer::~TCPServer() {
    stop();
}

bool TCPServer::start() {
    if (running_.exchange(true)) {
        return true; // Already running
    }
    
    if (!setup_server_socket()) {
        running_.store(false);
        return false;
    }
    
    // Start accepting connections
    accept_thread_ = std::thread(&TCPServer::accept_loop, this);
    
    if (config_.enable_logging) {
        log(ServerConfig::LogLevel::INFO, "Server started on " + 
            format_address(config_.host, config_.port));
    }
    
    return true;
}

void TCPServer::stop() {
    if (!running_.exchange(false)) {
        return; // Already stopped
    }
    
    // Close server socket
    if (server_socket_ != INVALID_SOCKET) {
        close(server_socket_);
        server_socket_ = INVALID_SOCKET;
    }
    
    // Wait for accept thread to finish
    if (accept_thread_.joinable()) {
        accept_thread_.join();
    }
    
    // Close all client connections
    {
        std::lock_guard<std::mutex> lock(connections_mutex_);
        for (auto& [socket, handler] : connections_) {
            handler->stop();
        }
        connections_.clear();
    }
    
    // Shutdown thread pools
    if (worker_pool_) {
        worker_pool_->shutdown();
    }
    if (io_pool_) {
        io_pool_->shutdown();
    }
    
    if (config_.enable_logging) {
        log(ServerConfig::LogLevel::INFO, "Server stopped");
    }
}

void TCPServer::reset_stats() {
    stats_ = ConnectionStats();
}

bool TCPServer::setup_server_socket() {
    // Create socket
    server_socket_ = socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket_ == INVALID_SOCKET) {
        log(ServerConfig::LogLevel::ERROR, "Failed to create socket: " + std::string(strerror(errno)));
        return false;
    }
    
    // Configure socket
    configure_socket(server_socket_);
    
    // Bind socket
    struct sockaddr_in server_addr{};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(config_.port);
    
    if (config_.host == "localhost" || config_.host == "127.0.0.1") {
        server_addr.sin_addr.s_addr = INADDR_LOOPBACK;
    } else if (config_.host == "0.0.0.0") {
        server_addr.sin_addr.s_addr = INADDR_ANY;
    } else {
        if (inet_pton(AF_INET, config_.host.c_str(), &server_addr.sin_addr) <= 0) {
            log(ServerConfig::LogLevel::ERROR, "Invalid host address: " + config_.host);
            close(server_socket_);
            return false;
        }
    }
    
    if (bind(server_socket_, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        log(ServerConfig::LogLevel::ERROR, "Failed to bind socket: " + std::string(strerror(errno)));
        close(server_socket_);
        return false;
    }
    
    // Listen for connections
    if (listen(server_socket_, config_.backlog) < 0) {
        log(ServerConfig::LogLevel::ERROR, "Failed to listen on socket: " + std::string(strerror(errno)));
        close(server_socket_);
        return false;
    }
    
    return true;
}

void TCPServer::configure_socket(int socket_fd) {
    // Enable address reuse
    int reuse = 1;
    setsockopt(socket_fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    // Enable port reuse (Linux-specific)
    if (config_.enable_so_reuseport) {
        setsockopt(socket_fd, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse));
    }
    
    // Configure TCP options
    if (config_.enable_tcp_nodelay) {
        setsockopt(socket_fd, IPPROTO_TCP, TCP_NODELAY, &reuse, sizeof(reuse));
    }
    
    if (config_.enable_tcp_keepalive) {
        setsockopt(socket_fd, SOL_SOCKET, SO_KEEPALIVE, &reuse, sizeof(reuse));
        
        int keepalive_time = config_.tcp_keepalive_idle;
        int keepalive_interval = config_.tcp_keepalive_interval;
        int keepalive_count = config_.tcp_keepalive_count;
        
        setsockopt(socket_fd, IPPROTO_TCP, TCP_KEEPIDLE, &keepalive_time, sizeof(keepalive_time));
        setsockopt(socket_fd, IPPROTO_TCP, TCP_KEEPINTVL, &keepalive_interval, sizeof(keepalive_interval));
        setsockopt(socket_fd, IPPROTO_TCP, TCP_KEEPCNT, &keepalive_count, sizeof(keepalive_count));
    }
    
    // Set buffer sizes
    int read_buffer_size = config_.read_buffer_size;
    int write_buffer_size = config_.write_buffer_size;
    setsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF, &read_buffer_size, sizeof(read_buffer_size));
    setsockopt(socket_fd, SOL_SOCKET, SO_SNDBUF, &write_buffer_size, sizeof(write_buffer_size));
}

void TCPServer::accept_loop() {
    while (running_.load()) {
        struct sockaddr_in client_addr{};
        socklen_t client_len = sizeof(client_addr);
        
        int client_socket = accept(server_socket_, (struct sockaddr*)&client_addr, &client_len);
        if (client_socket < 0) {
            if (running_.load()) {
                log(ServerConfig::LogLevel::ERROR, "Failed to accept connection: " + 
                    std::string(strerror(errno)));
            }
            continue;
        }
        
        // Check connection limit
        if (stats_.active_connections.load() >= config_.max_connections) {
            close(client_socket);
            continue;
        }
        
        // Configure client socket
        configure_socket(client_socket);
        
        // Handle new connection
        handle_new_connection(client_socket);
    }
}

void TCPServer::handle_new_connection(int client_socket) {
    stats_.total_connections.fetch_add(1);
    stats_.active_connections.fetch_add(1);
    
    // Create connection handler
    auto handler = std::make_unique<ConnectionHandler>(
        client_socket, cache_, command_registry_, config_);
    
    // Store connection
    {
        std::lock_guard<std::mutex> lock(connections_mutex_);
        connections_[client_socket] = std::move(handler);
    }
    
    // Start handling connection in thread pool
    worker_pool_->submit_detached([this, client_socket]() {
        ConnectionHandler* handler = nullptr;
        {
            std::lock_guard<std::mutex> lock(connections_mutex_);
            auto it = connections_.find(client_socket);
            if (it != connections_.end()) {
                handler = it->second.get();
            }
        }
        
        if (handler) {
            handler->start();
            
            // Update statistics
            stats_.total_requests.fetch_add(handler->get_requests_processed());
            stats_.bytes_read.fetch_add(handler->get_bytes_read());
            stats_.bytes_written.fetch_add(handler->get_bytes_written());
        }
        
        // Clean up connection
        cleanup_connection(client_socket);
    });
}

void TCPServer::cleanup_connection(int client_socket) {
    std::lock_guard<std::mutex> lock(connections_mutex_);
    connections_.erase(client_socket);
    stats_.active_connections.fetch_sub(1);
}

void TCPServer::log(ServerConfig::LogLevel level, const std::string& message) {
    if (!config_.enable_logging || level < config_.log_level) {
        return;
    }
    
    const char* level_str = "";
    switch (level) {
        case ServerConfig::LogLevel::DEBUG: level_str = "DEBUG"; break;
        case ServerConfig::LogLevel::INFO: level_str = "INFO"; break;
        case ServerConfig::LogLevel::WARN: level_str = "WARN"; break;
        case ServerConfig::LogLevel::ERROR: level_str = "ERROR"; break;
    }
    
    std::cout << "[" << level_str << "] " << message << std::endl;
}

std::string TCPServer::format_address(const std::string& host, uint16_t port) const {
    return host + ":" + std::to_string(port);
}

// ConnectionHandler implementation
ConnectionHandler::ConnectionHandler(int socket_fd, 
                                   std::shared_ptr<cache::Cache> cache,
                                   std::shared_ptr<CommandRegistry> registry,
                                   const ServerConfig& config)
    : socket_fd_(socket_fd), cache_(cache), registry_(registry), config_(config) {
    
    // Initialize buffers
    read_buffer_.resize(config_.read_buffer_size);
    write_buffer_.resize(config_.write_buffer_size);
    
    // Initialize protocol handlers
    parser_ = std::make_unique<protocol::RESPParser>(config_.read_buffer_size);
    serializer_ = std::make_unique<protocol::RESPSerializer>(config_.write_buffer_size);
    
    // Get remote address
    struct sockaddr_in addr{};
    socklen_t addr_len = sizeof(addr);
    if (getpeername(socket_fd_, (struct sockaddr*)&addr, &addr_len) == 0) {
        char addr_str[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &addr.sin_addr, addr_str, INET_ADDRSTRLEN);
        remote_address_ = std::string(addr_str) + ":" + std::to_string(ntohs(addr.sin_port));
    }
    
    update_last_activity();
}

ConnectionHandler::~ConnectionHandler() {
    stop();
}

void ConnectionHandler::start() {
    if (active_.exchange(true)) {
        return; // Already active
    }
    
    process_loop();
}

void ConnectionHandler::stop() {
    if (!active_.exchange(false)) {
        return; // Already stopped
    }
    
    if (socket_fd_ != INVALID_SOCKET) {
        close(socket_fd_);
        socket_fd_ = INVALID_SOCKET;
    }
}

void ConnectionHandler::process_loop() {
    while (active_.load()) {
        // Check for timeout
        if (is_connection_timed_out()) {
            break;
        }
        
        // Read data from socket
        if (!read_data()) {
            break;
        }
        
        // Process requests
        if (!process_requests()) {
            break;
        }
        
        // Write response data
        if (!write_data()) {
            break;
        }
    }
}

bool ConnectionHandler::read_data() {
    if (!is_socket_ready_for_read()) {
        return true; // No data available, but not an error
    }
    
    ssize_t bytes_read = recv(socket_fd_, read_buffer_.data() + read_pos_, 
                             read_buffer_.size() - read_pos_, MSG_DONTWAIT);
    
    if (bytes_read < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return true; // No data available
        }
        return false; // Error
    }
    
    if (bytes_read == 0) {
        return false; // Connection closed
    }
    
    read_pos_ += bytes_read;
    bytes_read_.fetch_add(bytes_read);
    update_last_activity();
    
    return true;
}

bool ConnectionHandler::write_data() {
    if (write_pos_ == 0) {
        return true; // Nothing to write
    }
    
    ssize_t bytes_written = send(socket_fd_, write_buffer_.data(), write_pos_, MSG_DONTWAIT);
    
    if (bytes_written < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return true; // Socket not ready for write
        }
        return false; // Error
    }
    
    bytes_written_.fetch_add(bytes_written);
    
    if (bytes_written == write_pos_) {
        write_pos_ = 0; // All data written
    } else {
        // Partial write, move remaining data
        std::memmove(write_buffer_.data(), write_buffer_.data() + bytes_written, 
                    write_pos_ - bytes_written);
        write_pos_ -= bytes_written;
    }
    
    update_last_activity();
    return true;
}

bool ConnectionHandler::process_requests() {
    if (read_pos_ == 0) {
        return true; // No data to process
    }
    
    // Parse RESP commands
    std::span<const char> data(read_buffer_.data(), read_pos_);
    auto command = parser_->parse_incremental(data);
    
    if (!command) {
        if (parser_->needs_more_data()) {
            return true; // Need more data
        }
        return false; // Parse error
    }
    
    // Handle command
    if (!handle_command(*command)) {
        return false;
    }
    
    // Remove processed data from buffer
    size_t consumed = parser_->bytes_consumed();
    if (consumed > 0) {
        std::memmove(read_buffer_.data(), read_buffer_.data() + consumed, read_pos_ - consumed);
        read_pos_ -= consumed;
    }
    
    return true;
}

bool ConnectionHandler::handle_command(const protocol::RESPValue& command) {
    requests_processed_.fetch_add(1);
    
    // Parse command
    auto parsed_command = protocol::CommandParser::parse_command(command);
    if (!parsed_command) {
        // Invalid command format
        serializer_->serialize_error("Invalid command format");
        return add_response_to_buffer();
    }
    
    // Execute command
    auto response = registry_->execute_command(parsed_command->name, parsed_command->args, cache_);
    
    // Serialize response
    serializer_->serialize(response);
    
    return add_response_to_buffer();
}

bool ConnectionHandler::add_response_to_buffer() {
    auto response_data = serializer_->data();
    
    // Check if response fits in write buffer
    if (write_pos_ + response_data.size() > write_buffer_.size()) {
        return false; // Buffer overflow
    }
    
    // Copy response to write buffer
    std::memcpy(write_buffer_.data() + write_pos_, response_data.data(), response_data.size());
    write_pos_ += response_data.size();
    
    // Clear serializer buffer
    serializer_->clear();
    
    return true;
}

bool ConnectionHandler::is_socket_ready_for_read() const {
    fd_set read_fds;
    FD_ZERO(&read_fds);
    FD_SET(socket_fd_, &read_fds);
    
    struct timeval timeout = {0, 0}; // Non-blocking
    return select(socket_fd_ + 1, &read_fds, nullptr, nullptr, &timeout) > 0;
}

bool ConnectionHandler::is_socket_ready_for_write() const {
    fd_set write_fds;
    FD_ZERO(&write_fds);
    FD_SET(socket_fd_, &write_fds);
    
    struct timeval timeout = {0, 0}; // Non-blocking
    return select(socket_fd_ + 1, nullptr, &write_fds, nullptr, &timeout) > 0;
}

void ConnectionHandler::update_last_activity() {
    last_activity_ = std::chrono::steady_clock::now();
}

bool ConnectionHandler::is_connection_timed_out() const {
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_activity_);
    return elapsed > config_.idle_timeout;
}

std::string ConnectionHandler::get_socket_address(int socket_fd) const {
    struct sockaddr_in addr{};
    socklen_t addr_len = sizeof(addr);
    if (getsockname(socket_fd, (struct sockaddr*)&addr, &addr_len) == 0) {
        char addr_str[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &addr.sin_addr, addr_str, INET_ADDRSTRLEN);
        return std::string(addr_str) + ":" + std::to_string(ntohs(addr.sin_port));
    }
    return "unknown";
}

// CommandRegistry implementation
CommandRegistry::CommandRegistry() {
    register_builtin_commands();
}

void CommandRegistry::register_command(const std::string& name, CommandHandler handler) {
    std::unique_lock<std::shared_mutex> lock(commands_mutex_);
    commands_[normalize_command_name(name)] = std::move(handler);
}

void CommandRegistry::unregister_command(const std::string& name) {
    std::unique_lock<std::shared_mutex> lock(commands_mutex_);
    commands_.erase(normalize_command_name(name));
}

protocol::RESPValue CommandRegistry::execute_command(const std::string& name,
                                                    const std::vector<std::string>& args,
                                                    std::shared_ptr<cache::Cache> cache) {
    std::string normalized_name = normalize_command_name(name);
    
    // Update statistics
    {
        std::unique_lock<std::shared_mutex> lock(stats_mutex_);
        command_stats_[normalized_name].fetch_add(1);
    }
    
    // Find and execute command
    {
        std::shared_lock<std::shared_mutex> lock(commands_mutex_);
        auto it = commands_.find(normalized_name);
        if (it != commands_.end()) {
            return it->second(args, cache);
        }
    }
    
    return create_error("Unknown command: " + name);
}

bool CommandRegistry::has_command(const std::string& name) const {
    std::shared_lock<std::shared_mutex> lock(commands_mutex_);
    return commands_.find(normalize_command_name(name)) != commands_.end();
}

std::vector<std::string> CommandRegistry::get_command_names() const {
    std::shared_lock<std::shared_mutex> lock(commands_mutex_);
    std::vector<std::string> names;
    names.reserve(commands_.size());
    for (const auto& [name, handler] : commands_) {
        names.push_back(name);
    }
    return names;
}

uint64_t CommandRegistry::get_command_count(const std::string& name) const {
    std::shared_lock<std::shared_mutex> lock(stats_mutex_);
    auto it = command_stats_.find(normalize_command_name(name));
    return it != command_stats_.end() ? it->second.load() : 0;
}

std::unordered_map<std::string, uint64_t> CommandRegistry::get_all_command_counts() const {
    std::shared_lock<std::shared_mutex> lock(stats_mutex_);
    std::unordered_map<std::string, uint64_t> result;
    for (const auto& [name, counter] : command_stats_) {
        result[name] = counter.load();
    }
    return result;
}

void CommandRegistry::reset_stats() {
    std::unique_lock<std::shared_mutex> lock(stats_mutex_);
    for (auto& [name, counter] : command_stats_) {
        counter.store(0);
    }
}

void CommandRegistry::register_builtin_commands() {
    register_command("PING", cmd_ping);
    register_command("GET", cmd_get);
    register_command("SET", cmd_set);
    register_command("DEL", cmd_del);
    register_command("EXISTS", cmd_exists);
    register_command("FLUSHALL", cmd_flushall);
    register_command("INFO", cmd_info);
    register_command("QUIT", cmd_quit);
}

// Built-in command implementations
protocol::RESPValue CommandRegistry::cmd_ping(const std::vector<std::string>& args,
                                             std::shared_ptr<cache::Cache> cache) {
    if (args.empty()) {
        return protocol::RESPValue(protocol::RESPType::SimpleString, "PONG");
    } else {
        return protocol::RESPValue(protocol::RESPType::BulkString, args[0]);
    }
}

protocol::RESPValue CommandRegistry::cmd_get(const std::vector<std::string>& args,
                                            std::shared_ptr<cache::Cache> cache) {
    if (args.size() != 1) {
        return create_error("Wrong number of arguments for GET command");
    }
    
    std::string value;
    if (cache->get(args[0], value)) {
        return protocol::RESPValue(protocol::RESPType::BulkString, value);
    } else {
        return create_null();
    }
}

protocol::RESPValue CommandRegistry::cmd_set(const std::vector<std::string>& args,
                                            std::shared_ptr<cache::Cache> cache) {
    if (args.size() < 2) {
        return create_error("Wrong number of arguments for SET command");
    }
    
    std::chrono::milliseconds ttl = std::chrono::milliseconds::zero();
    
    // Parse optional TTL arguments
    for (size_t i = 2; i < args.size(); i += 2) {
        if (i + 1 >= args.size()) {
            return create_error("Invalid SET command syntax");
        }
        
        if (args[i] == "EX") {
            try {
                int seconds = std::stoi(args[i + 1]);
                ttl = std::chrono::seconds(seconds);
            } catch (const std::exception&) {
                return create_error("Invalid expiration time");
            }
        } else if (args[i] == "PX") {
            try {
                int milliseconds = std::stoi(args[i + 1]);
                ttl = std::chrono::milliseconds(milliseconds);
            } catch (const std::exception&) {
                return create_error("Invalid expiration time");
            }
        }
    }
    
    if (cache->put(args[0], args[1], ttl)) {
        return create_ok();
    } else {
        return create_error("Failed to set key");
    }
}

protocol::RESPValue CommandRegistry::cmd_del(const std::vector<std::string>& args,
                                            std::shared_ptr<cache::Cache> cache) {
    if (args.empty()) {
        return create_error("Wrong number of arguments for DEL command");
    }
    
    int64_t deleted_count = 0;
    for (const auto& key : args) {
        if (cache->remove(key)) {
            deleted_count++;
        }
    }
    
    return protocol::RESPValue(protocol::RESPType::Integer, deleted_count);
}

protocol::RESPValue CommandRegistry::cmd_exists(const std::vector<std::string>& args,
                                               std::shared_ptr<cache::Cache> cache) {
    if (args.empty()) {
        return create_error("Wrong number of arguments for EXISTS command");
    }
    
    int64_t exists_count = 0;
    for (const auto& key : args) {
        if (cache->contains(key)) {
            exists_count++;
        }
    }
    
    return protocol::RESPValue(protocol::RESPType::Integer, exists_count);
}

protocol::RESPValue CommandRegistry::cmd_flushall(const std::vector<std::string>& args,
                                                  std::shared_ptr<cache::Cache> cache) {
    cache->clear();
    return create_ok();
}

protocol::RESPValue CommandRegistry::cmd_info(const std::vector<std::string>& args,
                                             std::shared_ptr<cache::Cache> cache) {
    auto stats = cache->get_stats();
    
    std::string info = "# Cache Statistics\r\n";
    info += "hits:" + std::to_string(stats.hits) + "\r\n";
    info += "misses:" + std::to_string(stats.misses) + "\r\n";
    info += "hit_rate:" + std::to_string(stats.hit_rate()) + "\r\n";
    info += "memory_entries:" + std::to_string(stats.memory_entries) + "\r\n";
    info += "memory_bytes:" + std::to_string(stats.memory_bytes) + "\r\n";
    info += "evictions:" + std::to_string(stats.evictions) + "\r\n";
    
    return protocol::RESPValue(protocol::RESPType::BulkString, info);
}

protocol::RESPValue CommandRegistry::cmd_quit(const std::vector<std::string>& args,
                                             std::shared_ptr<cache::Cache> cache) {
    return create_ok();
}

std::string CommandRegistry::normalize_command_name(const std::string& name) {
    std::string result = name;
    std::transform(result.begin(), result.end(), result.begin(), ::toupper);
    return result;
}

protocol::RESPValue CommandRegistry::create_error(const std::string& message) {
    return protocol::RESPValue(protocol::RESPType::Error, message);
}

protocol::RESPValue CommandRegistry::create_ok() {
    return protocol::RESPValue(protocol::RESPType::SimpleString, "OK");
}

protocol::RESPValue CommandRegistry::create_null() {
    return protocol::RESPValue(protocol::RESPType::Null);
}

} // namespace server
} // namespace meteor 