#include "dragonfly_connection.hpp"
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <errno.h>
#include <cstring>
#include <iostream>
#include <algorithm>

namespace garuda::network {

DragonflyConnection::DragonflyConnection(int socket_fd) 
    : socket_fd_(socket_fd)
    , read_buffer_(kBufferSize)
    , write_buffer_(kBufferSize)
    , parser_(std::make_unique<protocol::RespParser>()) {
    
    // Set socket to non-blocking mode
    int flags = fcntl(socket_fd_, F_GETFL, 0);
    fcntl(socket_fd_, F_SETFL, flags | O_NONBLOCK);
}

DragonflyConnection::~DragonflyConnection() {
    Close();
}

bool DragonflyConnection::ProcessData() {
    if (!alive_.load()) {
        return false;
    }
    
    // Read new data
    if (!ReadData()) {
        Close();
        return false;
    }
    
    // Process commands
    ProcessCommands();
    
    // Write pending responses
    if (!WriteData()) {
        Close();
        return false;
    }
    
    return alive_.load();
}

bool DragonflyConnection::ReadData() {
    while (true) {
        // Ensure we have space in the buffer
        if (read_pos_ >= read_buffer_.size() - 1024) {
            // Buffer is nearly full, need to compact or resize
            if (read_pos_ > 0) {
                // This shouldn't happen with proper command processing
                // but handle it gracefully
                read_pos_ = 0;
            } else {
                // Buffer is completely full with a single large command
                read_buffer_.resize(read_buffer_.size() * 2);
            }
        }
        
        ssize_t bytes_read = recv(socket_fd_, 
                                 read_buffer_.data() + read_pos_, 
                                 read_buffer_.size() - read_pos_, 
                                 MSG_DONTWAIT);
        
        if (bytes_read > 0) {
            read_pos_ += bytes_read;
        } else if (bytes_read == 0) {
            // Connection closed by peer
            return false;
        } else {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // No more data available right now
                break;
            } else {
                // Real error
                std::cerr << "recv() error: " << strerror(errno) << std::endl;
                return false;
            }
        }
    }
    
    return true;
}

bool DragonflyConnection::WriteData() {
    std::lock_guard<std::mutex> lock(write_mutex_);
    
    while (write_pos_ > 0) {
        ssize_t bytes_written = send(socket_fd_, 
                                   write_buffer_.data(), 
                                   write_pos_, 
                                   MSG_DONTWAIT | MSG_NOSIGNAL);
        
        if (bytes_written > 0) {
            // Move remaining data to front of buffer
            if (static_cast<size_t>(bytes_written) < write_pos_) {
                std::memmove(write_buffer_.data(), 
                           write_buffer_.data() + bytes_written,
                           write_pos_ - bytes_written);
            }
            write_pos_ -= bytes_written;
        } else {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // Socket buffer is full, try again later
                break;
            } else {
                // Real error
                std::cerr << "send() error: " << strerror(errno) << std::endl;
                return false;
            }
        }
    }
    
    return true;
}

void DragonflyConnection::ProcessCommands() {
    if (read_pos_ == 0) {
        return;
    }
    
    std::span<const char> data(read_buffer_.data(), read_pos_);
    size_t processed = 0;
    
    while (processed < read_pos_) {
        std::span<const char> remaining_data = data.subspan(processed);
        auto result = parser_->Parse(remaining_data);
        
        if (result.status == protocol::ParseStatus::OK) {
            HandleCommand(result.value);
            processed += result.consumed_bytes;
        } else if (result.status == protocol::ParseStatus::NEED_MORE_DATA) {
            // Need more data, wait for next read
            break;
        } else {
            // Parse error
            std::cerr << "RESP parse error: " << result.error_msg << std::endl;
            
            // Send error response and close connection
            auto error_response = protocol::RespValue::CreateError("ERR Protocol error");
            SendResponse(error_response);
            Close();
            return;
        }
    }
    
    // Compact read buffer
    if (processed > 0) {
        if (processed < read_pos_) {
            std::memmove(read_buffer_.data(), 
                       read_buffer_.data() + processed,
                       read_pos_ - processed);
        }
        read_pos_ -= processed;
    }
}

void DragonflyConnection::HandleCommand(const protocol::RespValue& command) {
    if (!command_handler_) {
        auto error_response = protocol::RespValue::CreateError("ERR No command handler");
        SendResponse(error_response);
        return;
    }
    
    try {
        auto response = command_handler_(command);
        SendResponse(response);
    } catch (const std::exception& e) {
        auto error_response = protocol::RespValue::CreateError("ERR " + std::string(e.what()));
        SendResponse(error_response);
    }
}

bool DragonflyConnection::SendResponse(const protocol::RespValue& response) {
    std::string serialized = protocol::RespSerializer::Serialize(response);
    
    std::lock_guard<std::mutex> lock(write_mutex_);
    
    // Check if we have space in write buffer
    if (write_pos_ + serialized.size() > write_buffer_.size()) {
        // Resize buffer if needed
        write_buffer_.resize(std::max(write_buffer_.size() * 2, write_pos_ + serialized.size()));
    }
    
    // Copy response to write buffer
    std::memcpy(write_buffer_.data() + write_pos_, serialized.data(), serialized.size());
    write_pos_ += serialized.size();
    
    return true;
}

void DragonflyConnection::Close() {
    if (alive_.exchange(false)) {
        if (socket_fd_ >= 0) {
            close(socket_fd_);
            socket_fd_ = -1;
        }
    }
}

// DragonflyServer implementation
DragonflyServer::DragonflyServer(int port) : port_(port) {}

DragonflyServer::~DragonflyServer() {
    Stop();
}

bool DragonflyServer::Start() {
    if (running_.load()) {
        return false; // Already running
    }
    
    if (!SetupServerSocket()) {
        return false;
    }
    
    // Create epoll instance
    epoll_fd_ = epoll_create1(EPOLL_CLOEXEC);
    if (epoll_fd_ == -1) {
        std::cerr << "epoll_create1() failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    running_.store(true);
    
    // Start accept thread
    accept_thread_ = std::thread(&DragonflyServer::AcceptLoop, this);
    
    // Start worker threads
    worker_threads_.reserve(kWorkerThreads);
    for (int i = 0; i < kWorkerThreads; ++i) {
        worker_threads_.emplace_back(&DragonflyServer::WorkerLoop, this);
    }
    
    std::cout << "Dragonfly server started on port " << port_ << std::endl;
    return true;
}

void DragonflyServer::Stop() {
    if (!running_.exchange(false)) {
        return; // Already stopped
    }
    
    std::cout << "Stopping Dragonfly server..." << std::endl;
    
    // Close server socket
    if (server_fd_ >= 0) {
        close(server_fd_);
        server_fd_ = -1;
    }
    
    // Close epoll
    if (epoll_fd_ >= 0) {
        close(epoll_fd_);
        epoll_fd_ = -1;
    }
    
    // Wait for threads to finish
    if (accept_thread_.joinable()) {
        accept_thread_.join();
    }
    
    for (auto& worker : worker_threads_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    
    // Close all connections
    std::lock_guard<std::mutex> lock(connections_mutex_);
    connections_.clear();
    
    std::cout << "Dragonfly server stopped" << std::endl;
}

void DragonflyServer::SetCommandHandler(DragonflyConnection::CommandHandler handler) {
    command_handler_ = std::move(handler);
}

bool DragonflyServer::SetupServerSocket() {
    server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd_ == -1) {
        std::cerr << "socket() failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    // Set socket options
    int opt = 1;
    if (setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) == -1) {
        std::cerr << "setsockopt(SO_REUSEADDR) failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    // Set non-blocking
    int flags = fcntl(server_fd_, F_GETFL, 0);
    fcntl(server_fd_, F_SETFL, flags | O_NONBLOCK);
    
    // Bind
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port_);
    
    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == -1) {
        std::cerr << "bind() failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    // Listen
    if (listen(server_fd_, SOMAXCONN) == -1) {
        std::cerr << "listen() failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    return true;
}

void DragonflyServer::AcceptLoop() {
    while (running_.load()) {
        sockaddr_in client_addr{};
        socklen_t client_len = sizeof(client_addr);
        
        int client_fd = accept4(server_fd_, 
                               reinterpret_cast<sockaddr*>(&client_addr), 
                               &client_len, 
                               SOCK_NONBLOCK);
        
        if (client_fd >= 0) {
            stats_.total_connections.fetch_add(1);
            stats_.active_connections.fetch_add(1);
            
            auto conn = std::make_shared<DragonflyConnection>(client_fd);
            conn->SetCommandHandler(command_handler_);
            
            // Add to epoll
            epoll_event event{};
            event.events = EPOLLIN | EPOLLOUT | EPOLLET;
            event.data.ptr = conn.get();
            
            if (epoll_ctl(epoll_fd_, EPOLL_CTL_ADD, client_fd, &event) == 0) {
                std::lock_guard<std::mutex> lock(connections_mutex_);
                connections_.push_back(conn);
            } else {
                std::cerr << "epoll_ctl() failed: " << strerror(errno) << std::endl;
                stats_.active_connections.fetch_sub(1);
            }
        } else {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                if (running_.load()) {
                    std::cerr << "accept4() failed: " << strerror(errno) << std::endl;
                }
            }
        }
        
        // Small delay to prevent busy waiting
        std::this_thread::sleep_for(std::chrono::microseconds(100));
    }
}

void DragonflyServer::WorkerLoop() {
    std::vector<epoll_event> events(kMaxEvents);
    
    while (running_.load()) {
        int nfds = epoll_wait(epoll_fd_, events.data(), kMaxEvents, 100);
        
        if (nfds == -1) {
            if (errno != EINTR && running_.load()) {
                std::cerr << "epoll_wait() failed: " << strerror(errno) << std::endl;
            }
            continue;
        }
        
        for (int i = 0; i < nfds; ++i) {
            auto* conn = static_cast<DragonflyConnection*>(events[i].data.ptr);
            
            if (events[i].events & (EPOLLIN | EPOLLOUT)) {
                if (!conn->ProcessData()) {
                    // Connection died, remove from epoll
                    epoll_ctl(epoll_fd_, EPOLL_CTL_DEL, conn->GetSocketFd(), nullptr);
                    stats_.active_connections.fetch_sub(1);
                    
                    // Remove from connections list
                    std::lock_guard<std::mutex> lock(connections_mutex_);
                    connections_.erase(
                        std::remove_if(connections_.begin(), connections_.end(),
                                     [conn](const std::weak_ptr<DragonflyConnection>& weak_conn) {
                                         auto shared_conn = weak_conn.lock();
                                         return !shared_conn || shared_conn.get() == conn;
                                     }),
                        connections_.end());
                }
            }
        }
    }
}

} // namespace garuda::network