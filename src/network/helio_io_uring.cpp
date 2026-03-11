#include "helio_io_uring.hpp"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <cstring>
#include <iostream>

namespace garuda::network {

IoUringContext::IoUringContext(unsigned entries) : entries_(entries) {}

IoUringContext::~IoUringContext() {
#ifdef HAVE_LIBURING
    if (initialized_) {
        io_uring_queue_exit(&ring_);
    }
#endif
}

bool IoUringContext::Initialize() {
#ifdef HAVE_LIBURING
    int ret = io_uring_queue_init(entries_, &ring_, 0);
    if (ret < 0) {
        std::cerr << "io_uring_queue_init failed: " << strerror(-ret) << std::endl;
        return false;
    }
    initialized_ = true;
    return true;
#else
    std::cerr << "io_uring not available, falling back to epoll" << std::endl;
    return false;
#endif
}

int IoUringContext::Submit() {
#ifdef HAVE_LIBURING
    if (!initialized_) return -1;
    return io_uring_submit(&ring_);
#else
    return -1;
#endif
}

int IoUringContext::WaitCompletion(int min_complete) {
#ifdef HAVE_LIBURING
    if (!initialized_) return -1;
    return io_uring_wait_cqe_nr(&ring_, nullptr, min_complete);
#else
    return -1;
#endif
}

bool IoUringContext::QueueAccept(int listen_fd, sockaddr* addr, socklen_t* addrlen, void* user_data) {
#ifdef HAVE_LIBURING
    if (!initialized_) return false;
    
    struct io_uring_sqe* sqe = io_uring_get_sqe(&ring_);
    if (!sqe) return false;
    
    io_uring_prep_accept(sqe, listen_fd, addr, addrlen, 0);
    io_uring_sqe_set_data(sqe, user_data);
    return true;
#else
    return false;
#endif
}

bool IoUringContext::QueueRead(int fd, void* buffer, size_t size, void* user_data) {
#ifdef HAVE_LIBURING
    if (!initialized_) return false;
    
    struct io_uring_sqe* sqe = io_uring_get_sqe(&ring_);
    if (!sqe) return false;
    
    io_uring_prep_read(sqe, fd, buffer, size, 0);
    io_uring_sqe_set_data(sqe, user_data);
    return true;
#else
    return false;
#endif
}

bool IoUringContext::QueueWrite(int fd, const void* buffer, size_t size, void* user_data) {
#ifdef HAVE_LIBURING
    if (!initialized_) return false;
    
    struct io_uring_sqe* sqe = io_uring_get_sqe(&ring_);
    if (!sqe) return false;
    
    io_uring_prep_write(sqe, fd, buffer, size, 0);
    io_uring_sqe_set_data(sqe, user_data);
    return true;
#else
    return false;
#endif
}

std::vector<IoUringContext::CompletionEvent> IoUringContext::GetCompletions() {
    std::vector<CompletionEvent> events;
    
#ifdef HAVE_LIBURING
    if (!initialized_) return events;
    
    struct io_uring_cqe* cqe;
    unsigned head;
    unsigned count = 0;
    
    io_uring_for_each_cqe(&ring_, head, cqe) {
        CompletionEvent event;
        event.user_data = io_uring_cqe_get_data(cqe);
        event.result = cqe->res;
        event.flags = cqe->flags;
        events.push_back(event);
        count++;
    }
    
    io_uring_cq_advance(&ring_, count);
#endif
    
    return events;
}

// FiberConnection implementation
FiberConnection::FiberConnection(int socket_fd, IoUringContext* io_context)
    : socket_fd_(socket_fd)
    , io_context_(io_context)
    , read_buffer_(kBufferSize)
    , write_buffer_(kBufferSize)
    , parser_(std::make_unique<protocol::RespParser>()) {
    
    // Set socket to non-blocking
    int flags = fcntl(socket_fd_, F_GETFL, 0);
    fcntl(socket_fd_, F_SETFL, flags | O_NONBLOCK);
}

FiberConnection::~FiberConnection() {
    if (socket_fd_ >= 0) {
        close(socket_fd_);
    }
}

void FiberConnection::Run() {
    // Main fiber loop
    while (alive_.load()) {
        // Try to read data asynchronously
        if (!AsyncRead(read_buffer_.data() + read_pos_, read_buffer_.size() - read_pos_)) {
            break;
        }
        
        // Process RESP commands
        if (!ProcessRespCommands()) {
            break;
        }
        
        // Write any pending responses
        if (write_pos_ > 0) {
            if (!AsyncWrite(write_buffer_.data(), write_pos_)) {
                break;
            }
            write_pos_ = 0;
        }
    }
}

bool FiberConnection::AsyncRead(void* buffer, size_t size) {
    // In a real implementation, this would use io_uring async read
    // For now, fall back to synchronous read
    ssize_t bytes_read = recv(socket_fd_, buffer, size, MSG_DONTWAIT);
    
    if (bytes_read > 0) {
        read_pos_ += bytes_read;
        return true;
    } else if (bytes_read == 0) {
        // Connection closed
        return false;
    } else {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            // Would block - in real implementation, yield fiber
            return true;
        } else {
            // Real error
            return false;
        }
    }
}

bool FiberConnection::AsyncWrite(const void* buffer, size_t size) {
    // In a real implementation, this would use io_uring async write
    ssize_t bytes_written = send(socket_fd_, buffer, size, MSG_DONTWAIT | MSG_NOSIGNAL);
    
    if (bytes_written > 0) {
        if (static_cast<size_t>(bytes_written) < size) {
            // Partial write - move remaining data
            std::memmove(write_buffer_.data(), 
                       static_cast<const char*>(buffer) + bytes_written,
                       size - bytes_written);
            write_pos_ = size - bytes_written;
        }
        return true;
    } else {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            // Would block - in real implementation, yield fiber
            return true;
        } else {
            // Real error
            return false;
        }
    }
}

bool FiberConnection::ProcessRespCommands() {
    if (read_pos_ == 0) return true;
    
    std::span<const char> data(read_buffer_.data(), read_pos_);
    size_t processed = 0;
    
    while (processed < read_pos_) {
        std::span<const char> remaining = data.subspan(processed);
        auto result = parser_->Parse(remaining);
        
        if (result.status == protocol::ParseStatus::OK) {
            // Handle command
            if (command_handler_) {
                auto response = command_handler_(result.value);
                std::string serialized = protocol::RespSerializer::Serialize(response);
                
                // Add to write buffer
                if (write_pos_ + serialized.size() <= write_buffer_.size()) {
                    std::memcpy(write_buffer_.data() + write_pos_, 
                              serialized.data(), serialized.size());
                    write_pos_ += serialized.size();
                }
            }
            processed += result.consumed_bytes;
        } else if (result.status == protocol::ParseStatus::NEED_MORE_DATA) {
            break;
        } else {
            // Parse error
            return false;
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
    
    return true;
}

// HelioProactorServer implementation
HelioProactorServer::HelioProactorServer(int port, int proactor_count)
    : port_(port), proactor_count_(proactor_count) {
    
    // Initialize io_uring contexts
    io_contexts_.reserve(proactor_count_);
    proactor_connections_.resize(proactor_count_);
    
    for (int i = 0; i < proactor_count_; ++i) {
        auto context = std::make_unique<IoUringContext>();
        if (!context->Initialize()) {
            std::cerr << "Warning: io_uring not available, performance will be limited" << std::endl;
        }
        io_contexts_.push_back(std::move(context));
    }
}

HelioProactorServer::~HelioProactorServer() {
    Stop();
}

bool HelioProactorServer::Start() {
    if (running_.load()) return false;
    
    if (!SetupServerSocket()) {
        return false;
    }
    
    running_.store(true);
    
    // Start proactor threads
    proactor_threads_.reserve(proactor_count_);
    for (int i = 0; i < proactor_count_; ++i) {
        proactor_threads_.emplace_back(&HelioProactorServer::ProactorLoop, this, i);
    }
    
    std::cout << "Helio Proactor Server started on port " << port_ 
              << " with " << proactor_count_ << " proactors" << std::endl;
    return true;
}

void HelioProactorServer::Stop() {
    if (!running_.exchange(false)) return;
    
    if (server_fd_ >= 0) {
        close(server_fd_);
        server_fd_ = -1;
    }
    
    // Wait for proactor threads
    for (auto& thread : proactor_threads_) {
        if (thread.joinable()) {
            thread.join();
        }
    }
    
    proactor_threads_.clear();
    proactor_connections_.clear();
}

void HelioProactorServer::SetCommandHandler(FiberConnection::CommandHandler handler) {
    command_handler_ = std::move(handler);
}

bool HelioProactorServer::SetupServerSocket() {
    server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd_ == -1) {
        std::cerr << "socket() failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    int opt = 1;
    if (setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) == -1) {
        std::cerr << "setsockopt(SO_REUSEADDR) failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    // Set non-blocking
    int flags = fcntl(server_fd_, F_GETFL, 0);
    fcntl(server_fd_, F_SETFL, flags | O_NONBLOCK);
    
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port_);
    
    if (bind(server_fd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == -1) {
        std::cerr << "bind() failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    if (listen(server_fd_, SOMAXCONN) == -1) {
        std::cerr << "listen() failed: " << strerror(errno) << std::endl;
        return false;
    }
    
    return true;
}

void HelioProactorServer::ProactorLoop(int proactor_id) {
    auto& io_context = io_contexts_[proactor_id];
    auto& connections = proactor_connections_[proactor_id];
    
    std::cout << "Proactor " << proactor_id << " started" << std::endl;
    
    while (running_.load()) {
        // Accept new connections (simplified - real implementation would use io_uring)
        sockaddr_in client_addr{};
        socklen_t client_len = sizeof(client_addr);
        
        int client_fd = accept4(server_fd_, 
                               reinterpret_cast<sockaddr*>(&client_addr), 
                               &client_len, 
                               SOCK_NONBLOCK);
        
        if (client_fd >= 0) {
            HandleNewConnection(client_fd, proactor_id);
        }
        
        // Process existing connections
        for (auto it = connections.begin(); it != connections.end();) {
            auto& conn = *it;
            if (!conn->IsAlive()) {
                it = connections.erase(it);
                stats_.active_connections.fetch_sub(1);
            } else {
                // In real implementation, this would be handled by fibers
                ++it;
            }
        }
        
        // Small delay to prevent busy waiting
        std::this_thread::sleep_for(std::chrono::microseconds(100));
    }
    
    std::cout << "Proactor " << proactor_id << " stopped" << std::endl;
}

void HelioProactorServer::HandleNewConnection(int client_fd, int proactor_id) {
    stats_.total_connections.fetch_add(1);
    stats_.active_connections.fetch_add(1);
    
    auto& connections = proactor_connections_[proactor_id];
    auto& io_context = io_contexts_[proactor_id];
    
    auto conn = std::make_unique<FiberConnection>(client_fd, io_context.get());
    conn->SetCommandHandler(command_handler_);
    
    connections.push_back(std::move(conn));
}

} // namespace garuda::network