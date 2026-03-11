/**
 * PHASE 7 STEP 1: DragonflyDB-Style Shared-Nothing Architecture with io_uring
 * 
 * CRITICAL ARCHITECTURAL REDESIGN:
 * - Thread-per-core model (exactly 1 thread per CPU core)
 * - Shared-nothing architecture (each thread owns its data completely)
 * - Direct processing (no cross-thread communication)
 * - Native io_uring integration (each thread has its own io_uring instance)
 * 
 * This implementation follows DragonflyDB's proven architecture that achieves
 * 6.43M ops/sec on 64 cores (100K+ ops/sec per core).
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

// Platform-specific includes
#ifdef __linux__
#define HAS_LINUX_EPOLL 1
#define HAS_IO_URING 1
#include <sys/epoll.h>
#include <sched.h>
#include <linux/time_types.h>
#include <liburing.h>
#else
#define HAS_LINUX_EPOLL 0
#define HAS_IO_URING 0
#endif

namespace meteor {

// **PHASE 7 STEP 1: DragonflyDB-Style Core Architecture**
class DragonflyCore {
public:
    DragonflyCore(int core_id, int port, size_t num_cores) 
        : core_id_(core_id), port_(port), num_cores_(num_cores), running_(false) {
        
        // **DRAGONFLY PRINCIPLE 1: Each core owns specific shards**
        // Calculate which shards this core owns
        for (size_t shard = 0; shard < num_cores_; ++shard) {
            if (shard % num_cores_ == static_cast<size_t>(core_id_)) {
                owned_shards_.push_back(shard);
            }
        }
        
        std::cout << "🔧 Core " << core_id_ << " owns " << owned_shards_.size() 
                  << " shards: ";
        for (size_t shard : owned_shards_) {
            std::cout << shard << " ";
        }
        std::cout << std::endl;
        
#if HAS_IO_URING
        // **DRAGONFLY PRINCIPLE 2: Each core has its own io_uring instance**
        if (io_uring_queue_init(URING_QUEUE_DEPTH, &ring_, 0) < 0) {
            std::cerr << "❌ Core " << core_id_ << " failed to initialize io_uring" << std::endl;
            use_io_uring_ = false;
        } else {
            use_io_uring_ = true;
            std::cout << "✅ Core " << core_id_ << " initialized io_uring with depth " 
                      << URING_QUEUE_DEPTH << std::endl;
        }
#else
        use_io_uring_ = false;
#endif

#if HAS_LINUX_EPOLL
        if (!use_io_uring_) {
            epoll_fd_ = epoll_create1(EPOLL_CLOEXEC);
            if (epoll_fd_ == -1) {
                std::cerr << "❌ Core " << core_id_ << " failed to create epoll" << std::endl;
            } else {
                std::cout << "✅ Core " << core_id_ << " using epoll fallback" << std::endl;
            }
        }
#endif
    }
    
    ~DragonflyCore() {
#if HAS_IO_URING
        if (use_io_uring_) {
            io_uring_queue_exit(&ring_);
        }
#endif
#if HAS_LINUX_EPOLL
        if (epoll_fd_ != -1) {
            close(epoll_fd_);
        }
#endif
        if (server_fd_ != -1) {
            close(server_fd_);
        }
    }
    
    // **DRAGONFLY PRINCIPLE 3: Direct key-to-core routing**
    bool owns_key(const std::string& key) const {
        size_t shard = std::hash<std::string>{}(key) % num_cores_;
        return std::find(owned_shards_.begin(), owned_shards_.end(), shard) != owned_shards_.end();
    }
    
    // **DRAGONFLY PRINCIPLE 4: Thread-per-core with CPU affinity**
    void start() {
        running_ = true;
        core_thread_ = std::thread([this]() {
            // **MANDATORY CPU AFFINITY (like DragonflyDB)**
            set_cpu_affinity();
            
            // **Create dedicated server socket with SO_REUSEPORT**
            create_server_socket();
            
            // **Run the core event loop**
            if (use_io_uring_) {
                run_io_uring_loop();
            } else {
                run_epoll_loop();
            }
        });
        
        std::cout << "🚀 Core " << core_id_ << " started with " 
                  << (use_io_uring_ ? "io_uring" : "epoll") << std::endl;
    }
    
    void stop() {
        running_ = false;
        if (core_thread_.joinable()) {
            core_thread_.join();
        }
        std::cout << "🛑 Core " << core_id_ << " stopped" << std::endl;
    }

private:
    static constexpr int URING_QUEUE_DEPTH = 256;
    static constexpr int MAX_EVENTS = 64;
    
    int core_id_;
    int port_;
    size_t num_cores_;
    std::vector<size_t> owned_shards_;
    std::atomic<bool> running_;
    std::thread core_thread_;
    
    // **SHARED-NOTHING DATA STORAGE**
    std::unordered_map<std::string, std::string> local_data_;
    
    // **NETWORK RESOURCES**
    int server_fd_ = -1;
    bool use_io_uring_ = false;
    
#if HAS_IO_URING
    struct io_uring ring_;
    std::unordered_map<uint64_t, int> pending_accepts_;
    std::unordered_map<uint64_t, int> pending_reads_;
    std::atomic<uint64_t> op_counter_{0};
#endif

#if HAS_LINUX_EPOLL
    int epoll_fd_ = -1;
#endif
    
    // **CLIENT CONNECTIONS WITH PIPELINE SUPPORT**
    std::unordered_map<int, std::string> client_buffers_;
    std::unordered_map<int, std::vector<std::string>> client_pipeline_commands_;
    std::unordered_map<int, std::string> client_pipeline_responses_;
    
    void set_cpu_affinity() {
#ifdef __linux__
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(core_id_, &cpuset);
        
        if (sched_setaffinity(0, sizeof(cpuset), &cpuset) == 0) {
            std::cout << "✅ Core " << core_id_ << " pinned to CPU " << core_id_ << std::endl;
        } else {
            std::cerr << "⚠️  Core " << core_id_ << " failed to set CPU affinity" << std::endl;
        }
#endif
    }
    
    void create_server_socket() {
        server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd_ == -1) {
            std::cerr << "❌ Core " << core_id_ << " failed to create socket" << std::endl;
            return;
        }
        
        // **SO_REUSEPORT: Each core gets its own server socket**
        int reuse = 1;
        if (setsockopt(server_fd_, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse)) < 0) {
            std::cerr << "❌ Core " << core_id_ << " failed to set SO_REUSEPORT" << std::endl;
        }
        
        // Non-blocking
        int flags = fcntl(server_fd_, F_GETFL, 0);
        fcntl(server_fd_, F_SETFL, flags | O_NONBLOCK);
        
        struct sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(port_);
        
        if (bind(server_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            std::cerr << "❌ Core " << core_id_ << " failed to bind to port " << port_ << std::endl;
            return;
        }
        
        if (listen(server_fd_, SOMAXCONN) < 0) {
            std::cerr << "❌ Core " << core_id_ << " failed to listen" << std::endl;
            return;
        }
        
        std::cout << "✅ Core " << core_id_ << " listening on port " << port_ 
                  << " with SO_REUSEPORT" << std::endl;
    }
    
#if HAS_IO_URING
    void run_io_uring_loop() {
        // Submit initial accept
        submit_accept();
        
        while (running_) {
            struct __kernel_timespec ts;
            ts.tv_sec = 0;
            ts.tv_nsec = 1000000; // 1ms timeout
            
            struct io_uring_cqe *cqe;
            int ret = io_uring_wait_cqe_timeout(&ring_, &cqe, &ts);
            
            if (ret == 0) {
                process_io_uring_completion(cqe);
                io_uring_cqe_seen(&ring_, cqe);
            } else if (ret != -ETIME) {
                std::cerr << "❌ Core " << core_id_ << " io_uring_wait_cqe failed: " 
                          << strerror(-ret) << std::endl;
                break;
            }
            
            // Submit any pending operations
            io_uring_submit(&ring_);
        }
    }
    
    void submit_accept() {
        struct io_uring_sqe *sqe = io_uring_get_sqe(&ring_);
        if (!sqe) {
            std::cerr << "❌ Core " << core_id_ << " no SQE available for accept" << std::endl;
            return;
        }
        
        uint64_t op_id = op_counter_.fetch_add(1);
        
        io_uring_prep_accept(sqe, server_fd_, nullptr, nullptr, 0);
        io_uring_sqe_set_data(sqe, reinterpret_cast<void*>(op_id));
        
        pending_accepts_[op_id] = server_fd_;
        
        std::cout << "🔄 Core " << core_id_ << " submitted accept (op_id=" << op_id << ")" << std::endl;
    }
    
    void submit_read(int client_fd) {
        struct io_uring_sqe *sqe = io_uring_get_sqe(&ring_);
        if (!sqe) {
            std::cerr << "❌ Core " << core_id_ << " no SQE available for read" << std::endl;
            return;
        }
        
        // **SIMPLE BUFFER MANAGEMENT**
        static thread_local char read_buffer[4096];
        
        uint64_t op_id = op_counter_.fetch_add(1);
        
        io_uring_prep_read(sqe, client_fd, read_buffer, sizeof(read_buffer), 0);
        io_uring_sqe_set_data(sqe, reinterpret_cast<void*>(op_id));
        
        pending_reads_[op_id] = client_fd;
        
        std::cout << "🔄 Core " << core_id_ << " submitted read for fd=" << client_fd 
                  << " (op_id=" << op_id << ")" << std::endl;
    }
    
    void process_io_uring_completion(struct io_uring_cqe *cqe) {
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
                client_pipeline_commands_[client_fd].clear();
                client_pipeline_responses_[client_fd] = "";
                submit_read(client_fd);
                
                // Submit next accept
                submit_accept();
            } else {
                std::cerr << "❌ Core " << core_id_ << " accept failed: " << strerror(-result) << std::endl;
                submit_accept(); // Keep accepting
            }
            return;
        }
        
        // **READ COMPLETION**  
        if (pending_reads_.count(op_id)) {
            int client_fd = pending_reads_[op_id];
            pending_reads_.erase(op_id);
            
            if (result > 0) {
                // **DRAGONFLY-STYLE PIPELINE PROCESSING**
                static thread_local char read_buffer[4096];
                std::string data(read_buffer, result);
                std::cout << "📥 Core " << core_id_ << " received " << result 
                          << " bytes from fd=" << client_fd << ": " << data << std::endl;
                
                // **ACCUMULATE DATA IN BUFFER**
                client_buffers_[client_fd] += data;
                
                // **PROCESS PIPELINE BATCH**
                process_pipeline_batch(client_fd);
                
                // Continue reading from this client
                submit_read(client_fd);
                
            } else if (result == 0) {
                std::cout << "🔌 Core " << core_id_ << " client fd=" << client_fd << " disconnected" << std::endl;
                client_buffers_.erase(client_fd);
                close(client_fd);
            } else {
                std::cerr << "❌ Core " << core_id_ << " read failed for fd=" << client_fd 
                          << ": " << strerror(-result) << std::endl;
                client_buffers_.erase(client_fd);
                close(client_fd);
            }
            return;
        }
        
        std::cerr << "❓ Core " << core_id_ << " unknown completion op_id=" << op_id << std::endl;
    }
#endif

#if HAS_LINUX_EPOLL
    void run_epoll_loop() {
        // Add server socket to epoll
        struct epoll_event ev;
        ev.events = EPOLLIN;
        ev.data.fd = server_fd_;
        epoll_ctl(epoll_fd_, EPOLL_CTL_ADD, server_fd_, &ev);
        
        struct epoll_event events[MAX_EVENTS];
        
        while (running_) {
            int nfds = epoll_wait(epoll_fd_, events, MAX_EVENTS, 1);
            
            for (int i = 0; i < nfds; ++i) {
                if (events[i].data.fd == server_fd_) {
                    handle_accept();
                } else {
                    handle_client_data(events[i].data.fd);
                }
            }
        }
    }
    
    void handle_accept() {
        while (true) {
            int client_fd = accept(server_fd_, nullptr, nullptr);
            if (client_fd == -1) {
                if (errno != EAGAIN && errno != EWOULDBLOCK) {
                    std::cerr << "❌ Core " << core_id_ << " accept error: " << strerror(errno) << std::endl;
                }
                break;
            }
            
            // Make client socket non-blocking
            int flags = fcntl(client_fd, F_GETFL, 0);
            fcntl(client_fd, F_SETFL, flags | O_NONBLOCK);
            
            // Add to epoll
            struct epoll_event ev;
            ev.events = EPOLLIN;
            ev.data.fd = client_fd;
            epoll_ctl(epoll_fd_, EPOLL_CTL_ADD, client_fd, &ev);
            
            client_buffers_[client_fd] = "";
            client_pipeline_commands_[client_fd].clear();
            client_pipeline_responses_[client_fd] = "";
            
            std::cout << "✅ Core " << core_id_ << " accepted connection fd=" << client_fd << std::endl;
        }
    }
    
    void handle_client_data(int client_fd) {
        char buffer[4096];
        ssize_t bytes_read = recv(client_fd, buffer, sizeof(buffer), 0);
        
        if (bytes_read > 0) {
            std::string data(buffer, bytes_read);
            std::cout << "📥 Core " << core_id_ << " received " << bytes_read 
                      << " bytes from fd=" << client_fd << ": " << data << std::endl;
            
            // **ACCUMULATE DATA IN BUFFER**
            client_buffers_[client_fd] += data;
            
            // **PROCESS PIPELINE BATCH**
            process_pipeline_batch(client_fd);
            
        } else if (bytes_read == 0) {
            std::cout << "🔌 Core " << core_id_ << " client fd=" << client_fd << " disconnected" << std::endl;
            epoll_ctl(epoll_fd_, EPOLL_CTL_DEL, client_fd, nullptr);
            client_buffers_.erase(client_fd);
            close(client_fd);
        } else {
            std::cerr << "❌ Core " << core_id_ << " recv error: " << strerror(errno) << std::endl;
            epoll_ctl(epoll_fd_, EPOLL_CTL_DEL, client_fd, nullptr);
            client_buffers_.erase(client_fd);
            close(client_fd);
        }
    }
#endif

    // **DRAGONFLY PRINCIPLE 5: Pipeline batch processing with proper RESP parsing**
    void process_pipeline_batch(int client_fd) {
        std::string& buffer = client_buffers_[client_fd];
        
        // **EXTRACT COMPLETE RESP COMMANDS FROM BUFFER**
        std::vector<std::vector<std::string>> commands;
        size_t pos = 0;
        
        while (pos < buffer.length()) {
            std::vector<std::string> command;
            size_t command_end = parse_resp_command(buffer, pos, command);
            
            if (command_end == std::string::npos) {
                // Incomplete command, wait for more data
                break;
            }
            
            if (!command.empty()) {
                commands.push_back(command);
            }
            pos = command_end;
        }
        
        // Remove processed data from buffer
        if (pos > 0) {
            buffer.erase(0, pos);
        }
        
        if (commands.empty()) {
            return; // No complete commands yet
        }
        
        std::cout << "🔄 Core " << core_id_ << " processing pipeline batch: " 
                  << commands.size() << " commands for fd=" << client_fd << std::endl;
        
        // **PROCESS ALL COMMANDS IN BATCH**
        std::string batch_response = "";
        for (const auto& command : commands) {
            std::string response = process_resp_command(command);
            batch_response += response;
        }
        
        // **SEND BATCH RESPONSE**
        if (!batch_response.empty()) {
            ssize_t sent = send(client_fd, batch_response.c_str(), batch_response.length(), MSG_NOSIGNAL);
            if (sent > 0) {
                std::cout << "📤 Core " << core_id_ << " sent pipeline batch: " 
                          << sent << " bytes (" << commands.size() << " responses) to fd=" << client_fd << std::endl;
            }
        }
    }
    
    // **PROPER RESP COMMAND PARSING**
    size_t parse_resp_command(const std::string& buffer, size_t start, std::vector<std::string>& command) {
        if (start >= buffer.length()) return std::string::npos;
        
        // Handle simple inline commands (like "PING\r\n")
        if (buffer[start] != '*') {
            size_t end = buffer.find("\r\n", start);
            if (end == std::string::npos) return std::string::npos;
            
            std::string line = buffer.substr(start, end - start);
            if (!line.empty()) {
                auto parts = split(line, ' ');
                command = parts;
            }
            return end + 2;
        }
        
        // Handle RESP arrays (*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n)
        size_t pos = start + 1; // Skip '*'
        
        // Parse array length
        size_t newline = buffer.find("\r\n", pos);
        if (newline == std::string::npos) return std::string::npos;
        
        int array_len = std::stoi(buffer.substr(pos, newline - pos));
        pos = newline + 2;
        
        // Parse each element
        for (int i = 0; i < array_len; i++) {
            if (pos >= buffer.length() || buffer[pos] != '$') return std::string::npos;
            pos++; // Skip '$'
            
            // Parse string length
            newline = buffer.find("\r\n", pos);
            if (newline == std::string::npos) return std::string::npos;
            
            int str_len = std::stoi(buffer.substr(pos, newline - pos));
            pos = newline + 2;
            
            // Parse string content
            if (pos + str_len + 2 > buffer.length()) return std::string::npos;
            
            std::string element = buffer.substr(pos, str_len);
            command.push_back(element);
            pos += str_len + 2; // Skip content + \r\n
        }
        
        return pos;
    }
    
    // **SINGLE COMMAND PROCESSING**
    std::string process_single_command(const std::string& command) {
        // Simple RESP parsing
        std::string trimmed = command;
        while (!trimmed.empty() && (trimmed.back() == '\r' || trimmed.back() == '\n')) {
            trimmed.pop_back();
        }
        
        if (trimmed.empty()) {
            return "";
        }
        
        std::cout << "🔍 Core " << core_id_ << " processing single command: '" << trimmed << "'" << std::endl;
        
        // **PING command**
        if (trimmed == "PING") {
            return "+PONG\r\n";
        }
        
        // **SET command**
        if (trimmed.substr(0, 3) == "SET") {
            auto parts = split(trimmed, ' ');
            if (parts.size() >= 3) {
                std::string key = parts[1];
                std::string value = parts[2];
                
                // **CHECK OWNERSHIP**
                if (!owns_key(key)) {
                    return "-ERR key belongs to different core\r\n";
                }
                
                local_data_[key] = value;
                std::cout << "✅ Core " << core_id_ << " stored: " << key << " = " << value << std::endl;
                return "+OK\r\n";
            }
        }
        
        // **GET command**
        if (trimmed.substr(0, 3) == "GET") {
            auto parts = split(trimmed, ' ');
            if (parts.size() >= 2) {
                std::string key = parts[1];
                
                // **CHECK OWNERSHIP**
                if (!owns_key(key)) {
                    return "-ERR key belongs to different core\r\n";
                }
                
                auto it = local_data_.find(key);
                if (it != local_data_.end()) {
                    return "+" + it->second + "\r\n";
                } else {
                    return "$-1\r\n";
                }
            }
        }
        
        return "-ERR unknown command\r\n";
    }
    
    // **RESP COMMAND PROCESSING (handles command arrays)**
    std::string process_resp_command(const std::vector<std::string>& command) {
        if (command.empty()) {
            return "";
        }
        
        std::string cmd = command[0];
        std::transform(cmd.begin(), cmd.end(), cmd.begin(), ::toupper);
        
        std::cout << "🔍 Core " << core_id_ << " processing RESP command: " << cmd;
        for (size_t i = 1; i < command.size(); i++) {
            std::cout << " " << command[i];
        }
        std::cout << std::endl;
        
        // **PING command**
        if (cmd == "PING") {
            return "+PONG\r\n";
        }
        
        // **SET command**
        if (cmd == "SET" && command.size() >= 3) {
            std::string key = command[1];
            std::string value = command[2];
            
            // **CHECK OWNERSHIP**
            if (!owns_key(key)) {
                return "-ERR key belongs to different core\r\n";
            }
            
            local_data_[key] = value;
            std::cout << "✅ Core " << core_id_ << " stored: " << key << " = " << value << std::endl;
            return "+OK\r\n";
        }
        
        // **GET command**
        if (cmd == "GET" && command.size() >= 2) {
            std::string key = command[1];
            
            // **CHECK OWNERSHIP**
            if (!owns_key(key)) {
                return "-ERR key belongs to different core\r\n";
            }
            
            auto it = local_data_.find(key);
            if (it != local_data_.end()) {
                std::cout << "✅ Core " << core_id_ << " retrieved: " << key << " = " << it->second << std::endl;
                return "$" + std::to_string(it->second.length()) + "\r\n" + it->second + "\r\n";
            } else {
                return "$-1\r\n"; // NULL
            }
        }
        
        // **CONFIG command (for redis-benchmark compatibility)**
        if (cmd == "CONFIG") {
            return "-ERR CONFIG not supported\r\n";
        }
        
        // **INFO command (for redis-benchmark compatibility)**
        if (cmd == "INFO") {
            return "$-1\r\n"; // NULL response
        }
        
        std::cout << "❌ Core " << core_id_ << " unknown command: " << cmd << std::endl;
        return "-ERR unknown command\r\n";
    }
    
    std::vector<std::string> split(const std::string& str, char delimiter) {
        std::vector<std::string> tokens;
        std::stringstream ss(str);
        std::string token;
        
        while (std::getline(ss, token, delimiter)) {
            if (!token.empty()) {
                tokens.push_back(token);
            }
        }
        
        return tokens;
    }
};

// **DRAGONFLY-STYLE SERVER**
class DragonflyServer {
public:
    DragonflyServer(int port, size_t num_cores) : port_(port), num_cores_(num_cores) {
        std::cout << "🚀 Initializing DragonflyDB-style server with " << num_cores_ 
                  << " cores on port " << port_ << std::endl;
        
        // **Create one core per CPU**
        for (size_t i = 0; i < num_cores_; ++i) {
            cores_.emplace_back(std::make_unique<DragonflyCore>(i, port_, num_cores_));
        }
    }
    
    void start() {
        std::cout << "🚀 Starting all " << num_cores_ << " cores..." << std::endl;
        
        for (auto& core : cores_) {
            core->start();
        }
        
        std::cout << "✅ DragonflyDB-style server started successfully!" << std::endl;
        std::cout << "🎯 Expected performance: ~" << (num_cores_ * 100) << "K RPS" << std::endl;
        std::cout << "📊 Architecture: " << num_cores_ << " cores, shared-nothing, " 
                  << (cores_[0] ? "io_uring" : "epoll") << std::endl;
    }
    
    void stop() {
        std::cout << "🛑 Stopping all cores..." << std::endl;
        
        for (auto& core : cores_) {
            core->stop();
        }
        
        std::cout << "✅ DragonflyDB-style server stopped" << std::endl;
    }
    
    void wait_for_shutdown() {
        std::cout << "🔄 Server running. Press Ctrl+C to stop." << std::endl;
        
        // Simple signal handling
        while (true) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }

private:
    int port_;
    size_t num_cores_;
    std::vector<std::unique_ptr<DragonflyCore>> cores_;
};

} // namespace meteor

// **MAIN FUNCTION**
int main(int argc, char* argv[]) {
    std::cout << "=== PHASE 7 STEP 1: DragonflyDB-Style Architecture ===" << std::endl;
    std::cout << "🎯 Target: 2.4M+ RPS with shared-nothing + io_uring" << std::endl;
    
    int port = 6379;
    size_t num_cores = std::thread::hardware_concurrency();
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "-p" && i + 1 < argc) {
            port = std::atoi(argv[++i]);
        } else if (arg == "-c" && i + 1 < argc) {
            num_cores = std::atoi(argv[++i]);
        } else if (arg == "-h" || arg == "--help") {
            std::cout << "Usage: " << argv[0] << " [-p port] [-c cores]" << std::endl;
            return 0;
        }
    }
    
    std::cout << "🔧 Configuration:" << std::endl;
    std::cout << "   Port: " << port << std::endl;
    std::cout << "   Cores: " << num_cores << std::endl;
    std::cout << "   Architecture: DragonflyDB shared-nothing" << std::endl;
    
    try {
        meteor::DragonflyServer server(port, num_cores);
        server.start();
        server.wait_for_shutdown();
        server.stop();
    } catch (const std::exception& e) {
        std::cerr << "❌ Server error: " << e.what() << std::endl;
        return 1;
    }
    
    return 0;
}