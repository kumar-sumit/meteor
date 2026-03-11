#include "meteor/server/tcp_server.hpp"
#include "meteor/protocol/resp_parser.hpp"
#include "meteor/utils/memory_pool.hpp"
#include "meteor/utils/thread_pool.hpp"
#include <algorithm>
#include <arpa/inet.h>
#include <fcntl.h>
#include <iostream>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

namespace meteor {
namespace server {

// ConnectionPool implementation
ConnectionPool::ConnectionPool(size_t max_size, size_t buffer_size)
    : max_size_(max_size)
    , buffer_size_(buffer_size)
    , pool_size_(0)
    , total_created_(0)
    , total_reused_(0)
    , running_(true)
{
    // Start cleanup thread
    cleanup_thread_ = std::thread(&ConnectionPool::cleanup_worker, this);
}

ConnectionPool::~ConnectionPool() {
    stop();
}

void ConnectionPool::stop() {
    running_ = false;
    
    if (cleanup_thread_.joinable()) {
        cleanup_thread_.join();
    }
    
    // Close all pooled connections
    std::unique_lock<std::mutex> lock(pool_mutex_);
    while (!available_connections_.empty()) {
        auto conn = available_connections_.front();
        available_connections_.pop();
        close(conn->fd);
        delete conn;
    }
}

std::unique_ptr<PooledConnection> ConnectionPool::get_connection() {
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    if (!available_connections_.empty()) {
        auto conn = std::unique_ptr<PooledConnection>(available_connections_.front());
        available_connections_.pop();
        pool_size_--;
        total_reused_++;
        
        // Update last used time
        conn->last_used = std::chrono::steady_clock::now();
        return conn;
    }
    
    // No available connections, create new one
    total_created_++;
    return nullptr; // Caller will create new connection
}

void ConnectionPool::return_connection(std::unique_ptr<PooledConnection> conn) {
    if (!conn || !running_) {
        return;
    }
    
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    if (pool_size_ < max_size_) {
        conn->last_used = std::chrono::steady_clock::now();
        available_connections_.push(conn.release());
        pool_size_++;
    } else {
        // Pool is full, close connection
        close(conn->fd);
    }
}

void ConnectionPool::cleanup_worker() {
    while (running_) {
        std::this_thread::sleep_for(std::chrono::seconds(60));
        cleanup_expired_connections();
    }
}

void ConnectionPool::cleanup_expired_connections() {
    std::unique_lock<std::mutex> lock(pool_mutex_);
    
    auto now = std::chrono::steady_clock::now();
    auto max_idle_time = std::chrono::minutes(5);
    
    std::queue<PooledConnection*> new_queue;
    
    while (!available_connections_.empty()) {
        auto conn = available_connections_.front();
        available_connections_.pop();
        
        if (now - conn->last_used > max_idle_time) {
            // Connection expired, close it
            close(conn->fd);
            delete conn;
            pool_size_--;
        } else {
            // Keep connection
            new_queue.push(conn);
        }
    }
    
    available_connections_ = std::move(new_queue);
}

ConnectionPoolStats ConnectionPool::get_stats() const {
    std::shared_lock<std::shared_mutex> lock(pool_stats_mutex_);
    return {
        pool_size_.load(),
        max_size_,
        total_created_.load(),
        total_reused_.load()
    };
}

// TCPServer implementation
TCPServer::TCPServer(const Config& config)
    : config_(config)
    , server_fd_(-1)
    , running_(false)
    , memory_pool_(std::make_unique<utils::MemoryPool>(config.memory_pool_size))
    , thread_pool_(std::make_unique<utils::ThreadPool>(config.worker_threads))
    , connection_pool_(std::make_unique<ConnectionPool>(config.max_connections, config.buffer_size))
    , active_connections_(0)
    , total_connections_(0)
    , total_requests_(0)
    , total_errors_(0)
{
}

TCPServer::~TCPServer() {
    stop();
}

bool TCPServer::start() {
    if (running_.exchange(true)) {
        return false; // Already running
    }
    
    // Create socket
    server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd_ < 0) {
        std::cerr << "Failed to create socket: " << strerror(errno) << std::endl;
        return false;
    }
    
    // Set socket options
    if (!configure_socket()) {
        close(server_fd_);
        return false;
    }
    
    // Bind socket
    sockaddr_in server_addr = {};
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(config_.port);
    
    if (bind(server_fd_, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        std::cerr << "Failed to bind socket: " << strerror(errno) << std::endl;
        close(server_fd_);
        return false;
    }
    
    // Listen
    if (listen(server_fd_, config_.backlog) < 0) {
        std::cerr << "Failed to listen: " << strerror(errno) << std::endl;
        close(server_fd_);
        return false;
    }
    
    std::cout << "🚀 Meteor server listening on " << config_.host << ":" << config_.port << std::endl;
    
    // Start accept loop
    accept_thread_ = std::thread(&TCPServer::accept_loop, this);
    
    return true;
}

void TCPServer::stop() {
    if (!running_.exchange(false)) {
        return; // Already stopped
    }
    
    // Close server socket
    if (server_fd_ >= 0) {
        close(server_fd_);
        server_fd_ = -1;
    }
    
    // Wait for accept thread
    if (accept_thread_.joinable()) {
        accept_thread_.join();
    }
    
    // Stop connection pool
    connection_pool_->stop();
    
    std::cout << "Server stopped gracefully" << std::endl;
}

void TCPServer::set_command_handler(CommandHandler handler) {
    command_handler_ = std::move(handler);
}

ServerStats TCPServer::get_stats() const {
    return {
        active_connections_.load(),
        total_connections_.load(),
        total_requests_.load(),
        total_errors_.load(),
        connection_pool_->get_stats()
    };
}

bool TCPServer::configure_socket() {
    // Enable SO_REUSEADDR
    int reuse = 1;
    if (setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
        std::cerr << "Failed to set SO_REUSEADDR: " << strerror(errno) << std::endl;
        return false;
    }
    
    // Enable SO_REUSEPORT if available
#ifdef SO_REUSEPORT
    if (setsockopt(server_fd_, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse)) < 0) {
        // Non-fatal, continue
        std::cerr << "Warning: Failed to set SO_REUSEPORT: " << strerror(errno) << std::endl;
    }
#endif
    
    // Set socket buffer sizes
    int buffer_size = config_.buffer_size;
    if (setsockopt(server_fd_, SOL_SOCKET, SO_RCVBUF, &buffer_size, sizeof(buffer_size)) < 0) {
        std::cerr << "Warning: Failed to set SO_RCVBUF: " << strerror(errno) << std::endl;
    }
    
    if (setsockopt(server_fd_, SOL_SOCKET, SO_SNDBUF, &buffer_size, sizeof(buffer_size)) < 0) {
        std::cerr << "Warning: Failed to set SO_SNDBUF: " << strerror(errno) << std::endl;
    }
    
    return true;
}

void TCPServer::accept_loop() {
    while (running_) {
        sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        
        int client_fd = accept(server_fd_, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            if (running_) {
                std::cerr << "Accept failed: " << strerror(errno) << std::endl;
            }
            continue;
        }
        
        // Configure client socket
        if (!configure_client_socket(client_fd)) {
            close(client_fd);
            continue;
        }
        
        // Get client IP
        char client_ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &client_addr.sin_addr, client_ip, INET_ADDRSTRLEN);
        
        total_connections_++;
        active_connections_++;
        
        if (config_.enable_logging) {
            std::cout << "Client connected: " << client_ip << ":" << ntohs(client_addr.sin_port) << std::endl;
        }
        
        // Handle connection in thread pool
        thread_pool_->enqueue([this, client_fd, client_ip]() {
            handle_connection(client_fd, client_ip);
        });
    }
}

bool TCPServer::configure_client_socket(int client_fd) {
    // Enable TCP_NODELAY for low latency
    int nodelay = 1;
    if (setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay)) < 0) {
        std::cerr << "Warning: Failed to set TCP_NODELAY: " << strerror(errno) << std::endl;
    }
    
    // Set keep-alive
    int keepalive = 1;
    if (setsockopt(client_fd, SOL_SOCKET, SO_KEEPALIVE, &keepalive, sizeof(keepalive)) < 0) {
        std::cerr << "Warning: Failed to set SO_KEEPALIVE: " << strerror(errno) << std::endl;
    }
    
    // Set socket buffer sizes
    int buffer_size = config_.buffer_size;
    if (setsockopt(client_fd, SOL_SOCKET, SO_RCVBUF, &buffer_size, sizeof(buffer_size)) < 0) {
        std::cerr << "Warning: Failed to set client SO_RCVBUF: " << strerror(errno) << std::endl;
    }
    
    if (setsockopt(client_fd, SOL_SOCKET, SO_SNDBUF, &buffer_size, sizeof(buffer_size)) < 0) {
        std::cerr << "Warning: Failed to set client SO_SNDBUF: " << strerror(errno) << std::endl;
    }
    
    return true;
}

void TCPServer::handle_connection(int client_fd, const std::string& client_ip) {
    // Create or get pooled connection
    auto pooled_conn = connection_pool_->get_connection();
    std::unique_ptr<PooledConnection> conn;
    
    if (pooled_conn) {
        conn = std::move(pooled_conn);
        conn->fd = client_fd;
    } else {
        conn = std::make_unique<PooledConnection>();
        conn->fd = client_fd;
        conn->parser = std::make_unique<protocol::RESPParser>(*memory_pool_);
        conn->serializer = std::make_unique<protocol::RESPSerializer>(*memory_pool_);
        conn->read_buffer.resize(config_.buffer_size);
        conn->write_buffer.reserve(config_.buffer_size);
        conn->last_used = std::chrono::steady_clock::now();
    }
    
    // Connection handling loop
    while (running_) {
        // Read data
        ssize_t bytes_read = recv(client_fd, conn->read_buffer.data(), conn->read_buffer.size(), 0);
        
        if (bytes_read <= 0) {
            if (bytes_read == 0) {
                if (config_.enable_logging) {
                    std::cout << "Client disconnected: " << client_ip << std::endl;
                }
            } else {
                if (config_.enable_logging) {
                    std::cout << "Read error: " << strerror(errno) << std::endl;
                }
                total_errors_++;
            }
            break;
        }
        
        // Parse RESP commands
        std::string_view data(conn->read_buffer.data(), bytes_read);
        
        while (!data.empty()) {
            auto parse_result = conn->parser->parse(data);
            
            if (parse_result.status == protocol::ParseStatus::NEED_MORE_DATA) {
                break;
            }
            
            if (parse_result.status == protocol::ParseStatus::ERROR) {
                // Send error response
                auto error_response = protocol::create_error("ERR Protocol error");
                auto serialized = conn->serializer->serialize(error_response);
                
                send(client_fd, serialized.data(), serialized.size(), MSG_NOSIGNAL);
                total_errors_++;
                break;
            }
            
            if (parse_result.status == protocol::ParseStatus::COMPLETE) {
                // Process command
                total_requests_++;
                
                if (command_handler_) {
                    auto response = command_handler_(parse_result.value);
                    auto serialized = conn->serializer->serialize(response);
                    
                    if (send(client_fd, serialized.data(), serialized.size(), MSG_NOSIGNAL) < 0) {
                        if (config_.enable_logging) {
                            std::cout << "Send error: " << strerror(errno) << std::endl;
                        }
                        total_errors_++;
                        goto connection_end;
                    }
                } else {
                    // No command handler, send error
                    auto error_response = protocol::create_error("ERR No command handler");
                    auto serialized = conn->serializer->serialize(error_response);
                    send(client_fd, serialized.data(), serialized.size(), MSG_NOSIGNAL);
                }
                
                // Remove processed data
                data.remove_prefix(parse_result.bytes_consumed);
            }
        }
    }
    
connection_end:
    // Close connection
    close(client_fd);
    active_connections_--;
    
    // Return connection to pool (parser and serializer will be reused)
    conn->fd = -1; // Mark as closed
    connection_pool_->return_connection(std::move(conn));
}

} // namespace server
} // namespace meteor 