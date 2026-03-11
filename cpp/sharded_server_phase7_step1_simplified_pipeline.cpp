/**
 * PHASE 7 STEP 1: Simplified DragonflyDB Pipeline (Focus on Working Pipeline)
 * 
 * SIMPLIFIED APPROACH:
 * - Start with working basic architecture
 * - Add proper pipeline processing step by step
 * - Focus on getting 3x improvement working
 */

#include <iostream>
#include <memory>
#include <vector>
#include <string>
#include <unordered_map>
#include <thread>
#include <atomic>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <algorithm>
#include <cstring>
#include <functional>
#include <random>
#include <queue>
#include <sstream>

// Network includes
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <csignal>

// Platform-specific includes
#ifdef __linux__
#include <sys/epoll.h>
#include <sched.h>
#endif

#if HAS_IO_URING
#include <liburing.h>
#include <linux/time_types.h>
#endif

// Global server fd for io_uring accept operations
int g_server_fd = -1;

// **DRAGONFLY PRINCIPLE 1: Thread-per-core with shared-nothing**
class CoreThread {
private:
    int core_id_;
    std::atomic<bool> running_{false};
    std::thread thread_;
    
    // **DRAGONFLY PRINCIPLE 2: Each core owns its data completely**
    std::unordered_map<std::string, std::string> local_data_;
    
    // **DRAGONFLY PRINCIPLE 3: Direct I/O handling (io_uring per core)**
#if HAS_IO_URING
    struct io_uring ring_;
    std::unordered_map<uint64_t, int> pending_accepts_;
    std::unordered_map<uint64_t, int> pending_reads_;
    std::unordered_map<uint64_t, int> pending_writes_;
    std::atomic<uint64_t> operation_counter_{1};
#endif

#if HAS_LINUX_EPOLL
    int epoll_fd_ = -1;
#endif
    
    // **CLIENT CONNECTIONS WITH SIMPLIFIED PIPELINE SUPPORT**
    std::unordered_map<int, std::string> client_buffers_;
    
    void set_cpu_affinity() {
#ifdef __linux__
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(core_id_, &cpuset);
        
        if (sched_setaffinity(0, sizeof(cpuset), &cpuset) == 0) {
            std::cout << "✅ Core " << core_id_ << " CPU affinity set" << std::endl;
        } else {
            std::cerr << "❌ Core " << core_id_ << " failed to set CPU affinity" << std::endl;
        }
#endif
    }
    
    void setup_io() {
#if HAS_IO_URING
        if (io_uring_queue_init(256, &ring_, 0) == 0) {
            std::cout << "✅ Core " << core_id_ << " initialized io_uring with depth 256" << std::endl;
        } else {
            std::cerr << "❌ Core " << core_id_ << " failed to initialize io_uring" << std::endl;
            return;
        }
#endif

#if HAS_LINUX_EPOLL
        epoll_fd_ = epoll_create1(0);
        if (epoll_fd_ == -1) {
            std::cerr << "❌ Core " << core_id_ << " failed to create epoll" << std::endl;
            return;
        }
#endif
    }
    
    void run() {
        set_cpu_affinity();
        setup_io();
        
#if HAS_IO_URING
        std::cout << "🚀 Core " << core_id_ << " started with io_uring" << std::endl;
        run_io_uring_loop();
#elif HAS_LINUX_EPOLL
        std::cout << "🚀 Core " << core_id_ << " started with epoll" << std::endl;
        run_epoll_loop();
#endif
    }

#if HAS_IO_URING
    void submit_accept() {
        struct io_uring_sqe *sqe = io_uring_get_sqe(&ring_);
        if (!sqe) return;
        
        // Get server fd from main thread (stored in a static variable)
        extern int g_server_fd;
        int server_fd = g_server_fd;
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        
        uint64_t op_id = operation_counter_.fetch_add(1);
        io_uring_prep_accept(sqe, server_fd, (struct sockaddr*)&client_addr, &client_len, 0);
        io_uring_sqe_set_data(sqe, reinterpret_cast<void*>(op_id));
        
        pending_accepts_[op_id] = server_fd;
        io_uring_submit(&ring_);
    }
    
    void submit_read(int client_fd) {
        struct io_uring_sqe *sqe = io_uring_get_sqe(&ring_);
        if (!sqe) return;
        
        static thread_local char read_buffer[4096];
        uint64_t op_id = operation_counter_.fetch_add(1);
        
        io_uring_prep_recv(sqe, client_fd, read_buffer, sizeof(read_buffer), 0);
        io_uring_sqe_set_data(sqe, reinterpret_cast<void*>(op_id));
        
        pending_reads_[op_id] = client_fd;
        io_uring_submit(&ring_);
    }
    
    void run_io_uring_loop() {
        submit_accept(); // Start accepting connections
        
        struct __kernel_timespec ts;
        ts.tv_sec = 0;
        ts.tv_nsec = 10000000; // 10ms
        
        while (running_.load()) {
            struct io_uring_cqe *cqe;
            int ret = io_uring_wait_cqe_timeout(&ring_, &cqe, &ts);
            
            if (ret == 0) {
                process_completion(cqe);
                io_uring_cqe_seen(&ring_, cqe);
            }
        }
    }
    
    void process_completion(struct io_uring_cqe *cqe) {
        uint64_t op_id = reinterpret_cast<uint64_t>(io_uring_cqe_get_data(cqe));
        int result = cqe->res;
        
        // **ACCEPT COMPLETION**
        if (pending_accepts_.count(op_id)) {
            pending_accepts_.erase(op_id);
            
            if (result > 0) {
                int client_fd = result;
                std::cout << "✅ Core " << core_id_ << " accepted connection fd=" << client_fd << std::endl;
                
                // **DIRECT PROCESSING: No cross-thread communication**
                client_buffers_[client_fd] = "";
                submit_read(client_fd);
                
                // Submit next accept
                submit_accept();
            } else {
                std::cerr << "❌ Core " << core_id_ << " accept failed: " << strerror(-result) << std::endl;
                submit_accept(); // Retry accept
            }
            return;
        }
        
        // **READ COMPLETION**  
        if (pending_reads_.count(op_id)) {
            int client_fd = pending_reads_[op_id];
            pending_reads_.erase(op_id);
            
            if (result > 0) {
                // **SIMPLIFIED PIPELINE PROCESSING**
                static thread_local char read_buffer[4096];
                std::string data(read_buffer, result);
                std::cout << "📥 Core " << core_id_ << " received " << result 
                          << " bytes from fd=" << client_fd << ": '" << data << "'" << std::endl;
                
                // **ACCUMULATE DATA IN BUFFER**
                client_buffers_[client_fd] += data;
                
                // **PROCESS COMPLETE COMMANDS**
                process_commands(client_fd);
                
                // Continue reading from this client
                submit_read(client_fd);
                
            } else if (result == 0) {
                std::cout << "🔌 Core " << core_id_ << " client fd=" << client_fd << " disconnected" << std::endl;
                client_buffers_.erase(client_fd);
                close(client_fd);
            } else {
                std::cerr << "❌ Core " << core_id_ << " read error: " << strerror(-result) << std::endl;
                client_buffers_.erase(client_fd);
                close(client_fd);
            }
            return;
        }
    }
#endif

    // **SIMPLIFIED PIPELINE COMMAND PROCESSING**
    void process_commands(int client_fd) {
        std::string& buffer = client_buffers_[client_fd];
        std::string responses = "";
        int commands_processed = 0;
        
        std::cout << "🔍 Core " << core_id_ << " processing buffer: '" << buffer << "' (length=" << buffer.length() << ")" << std::endl;
        
        // **SIMPLE LINE-BASED PARSING (handles both inline and basic RESP)**
        size_t pos = 0;
        while ((pos = buffer.find("\r\n")) != std::string::npos) {
            std::string line = buffer.substr(0, pos);
            buffer.erase(0, pos + 2);
            
            std::cout << "🔍 Core " << core_id_ << " extracted line: '" << line << "'" << std::endl;
            
            if (!line.empty()) {
                std::string response = process_single_command(line);
                if (!response.empty()) {
                    responses += response;
                    commands_processed++;
                    std::cout << "✅ Core " << core_id_ << " generated response: '" << response << "'" << std::endl;
                }
            }
        }
        
        std::cout << "🔍 Core " << core_id_ << " remaining buffer: '" << buffer << "'" << std::endl;
        
        // **BATCH RESPONSE SENDING**
        if (!responses.empty()) {
            std::cout << "📤 Core " << core_id_ << " sending " << commands_processed 
                      << " responses (" << responses.length() << " bytes) to fd=" << client_fd << std::endl;
            
            ssize_t sent = send(client_fd, responses.c_str(), responses.length(), MSG_NOSIGNAL);
            if (sent <= 0) {
                std::cerr << "❌ Core " << core_id_ << " send failed for fd=" << client_fd << std::endl;
                client_buffers_.erase(client_fd);
                close(client_fd);
            }
        }
    }
    
    // **SIMPLIFIED COMMAND PROCESSING**
    std::string process_single_command(const std::string& line) {
        // Handle both "PING" and "*1\r\n$4\r\nPING\r\n" formats
        std::string cmd = line;
        
        // Trim whitespace first
        while (!cmd.empty() && (cmd.back() == '\r' || cmd.back() == '\n' || cmd.back() == ' ')) {
            cmd.pop_back();
        }
        while (!cmd.empty() && (cmd.front() == '\r' || cmd.front() == '\n' || cmd.front() == ' ')) {
            cmd.erase(0, 1);
        }
        
        // Simple RESP array parsing for "*1\r\n$4\r\nPING\r\n" -> "PING"
        if (cmd.length() > 0 && cmd[0] == '*') {
            // For now, just extract simple commands
            if (cmd.find("PING") != std::string::npos) {
                cmd = "PING";
            } else if (cmd.find("SET") != std::string::npos) {
                cmd = "SET key value"; // Simplified
            } else if (cmd.find("GET") != std::string::npos) {
                cmd = "GET key"; // Simplified
            }
        }
        
        std::cout << "🔍 Core " << core_id_ << " processing: '" << cmd << "' (original: '" << line << "')" << std::endl;
        
        // **PING command**
        if (cmd == "PING") {
            return "+PONG\r\n";
        }
        
        // **SET command (simplified)**
        if (cmd.find("SET") == 0) {
            // For demo purposes, just store a fixed key-value
            std::string key = "demo_key_" + std::to_string(core_id_);
            std::string value = "demo_value";
            
            if (owns_key(key)) {
                local_data_[key] = value;
                std::cout << "✅ Core " << core_id_ << " stored: " << key << " = " << value << std::endl;
                return "+OK\r\n";
            }
        }
        
        // **GET command (simplified)**
        if (cmd.find("GET") == 0) {
            std::string key = "demo_key_" + std::to_string(core_id_);
            
            if (owns_key(key)) {
                auto it = local_data_.find(key);
                if (it != local_data_.end()) {
                    std::cout << "✅ Core " << core_id_ << " retrieved: " << key << " = " << it->second << std::endl;
                    return "$" + std::to_string(it->second.length()) + "\r\n" + it->second + "\r\n";
                } else {
                    return "$-1\r\n"; // NULL
                }
            }
        }
        
        return "-ERR unknown command\r\n";
    }
    
    // **DRAGONFLY PRINCIPLE 4: Key ownership (shared-nothing)**
    bool owns_key(const std::string& key) {
        // Simple hash-based sharding
        std::hash<std::string> hasher;
        return (hasher(key) % 4) == static_cast<size_t>(core_id_);
    }

public:
    CoreThread(int core_id) : core_id_(core_id) {}
    
    void start() {
        running_.store(true);
        thread_ = std::thread(&CoreThread::run, this);
    }
    
    void stop() {
        running_.store(false);
        if (thread_.joinable()) {
            thread_.join();
        }
        
#if HAS_IO_URING
        io_uring_queue_exit(&ring_);
#endif
#if HAS_LINUX_EPOLL
        if (epoll_fd_ != -1) {
            close(epoll_fd_);
        }
#endif
    }
};

// **DRAGONFLY PRINCIPLE 0: Main server orchestration**
class DragonflyServer {
private:
    int port_;
    int num_cores_;
    std::vector<std::unique_ptr<CoreThread>> cores_;
    std::atomic<bool> running_{false};
    int server_fd_ = -1;
    
public:
    DragonflyServer(int port, int num_cores) : port_(port), num_cores_(num_cores) {}
    
    bool start() {
        // Create server socket
        server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd_ < 0) {
            std::cerr << "❌ Failed to create server socket" << std::endl;
            return false;
        }
        
        int opt = 1;
        setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        setsockopt(server_fd_, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
        
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(port_);
        
        if (bind(server_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            std::cerr << "❌ Failed to bind to port " << port_ << std::endl;
            close(server_fd_);
            return false;
        }
        
        if (listen(server_fd_, 1024) < 0) {
            std::cerr << "❌ Failed to listen on port " << port_ << std::endl;
            close(server_fd_);
            return false;
        }
        
        std::cout << "🚀 DragonflyDB-style server listening on port " << port_ << std::endl;
        
        // **Set global server fd for io_uring accept operations**
        g_server_fd = server_fd_;
        
        // **Start all core threads**
        cores_.reserve(num_cores_);
        for (int i = 0; i < num_cores_; i++) {
            cores_.push_back(std::make_unique<CoreThread>(i));
            cores_[i]->start();
        }
        
        running_.store(true);
        return true;
    }
    
    void stop() {
        running_.store(false);
        
        // Stop all core threads
        for (auto& core : cores_) {
            core->stop();
        }
        
        if (server_fd_ != -1) {
            close(server_fd_);
        }
        
        std::cout << "🛑 DragonflyDB-style server stopped" << std::endl;
    }
    
    void wait_for_shutdown() {
        while (running_.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }
};

int main(int argc, char* argv[]) {
    int port = 6379;
    int num_cores = 4;
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            port = std::stoi(argv[i + 1]);
            i++;
        } else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            num_cores = std::stoi(argv[i + 1]);
            i++;
        }
    }
    
    std::cout << "🚀 Starting DragonflyDB-style server on port " << port 
              << " with " << num_cores << " cores" << std::endl;
    
    DragonflyServer server(port, num_cores);
    
    if (!server.start()) {
        std::cerr << "❌ Failed to start server" << std::endl;
        return 1;
    }
    
    // Handle Ctrl+C gracefully
    signal(SIGINT, [](int) {
        std::cout << "\n🛑 Shutting down server..." << std::endl;
        exit(0);
    });
    
    server.wait_for_shutdown();
    server.stop();
    
    return 0;
}