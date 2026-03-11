// **PHASE 7 STEP 1: CLEAN io_uring Implementation (DragonflyDB Style)**
// Building on Phase 6 Step 3 (proven working baseline) with:
// - Pure io_uring network I/O (NO epoll/kqueue fallback)
// - Preserves ALL Phase 6 Step 3 optimizations (pipeline batching, CPU affinity, etc.)
// - DragonflyDB-style async I/O with batched operations
// - Optimized network I/O with minimal syscall overhead
// - Target: Beat DragonflyDB performance (1.5M+ RPS)

#include <iostream>
#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <thread>
#include <mutex>
#include <shared_mutex>
#include <condition_variable>
#include <unordered_map>
#include <queue>
#include <sstream>
#include <chrono>
#include <algorithm>
#include <cstring>
#include <csignal>
#include <getopt.h>
#include <fstream>
#include <array>
#include <optional>
#include <functional>
#include <random>

// **PHASE 6 STEP 1: AVX-512 and Advanced Performance Includes**
#include <immintrin.h>  // AVX-512 SIMD instructions
#include <x86intrin.h>  // Additional SIMD intrinsics

// Network includes
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

// **PHASE 7 STEP 1: Pure io_uring (Linux-only, DragonflyDB style)**
#ifdef __linux__
#include <liburing.h>
#include <linux/time_types.h>
#include <sched.h>
#include <pthread.h>
#include <emmintrin.h>  // For _mm_pause()
#define HAS_IO_URING 1
#else
#error "Pure io_uring implementation requires Linux with io_uring support"
#endif

namespace meteor {

// **Keep all Phase 6 Step 3 SIMD optimizations**
namespace simd {
    // Check for AVX-512 support at runtime
    inline bool has_avx512() {
        static bool checked = false;
        static bool has_support = false;
        if (!checked) {
            __builtin_cpu_init();
            has_support = __builtin_cpu_supports("avx512f") && 
                         __builtin_cpu_supports("avx512vl") &&
                         __builtin_cpu_supports("avx512bw");
            checked = true;
        }
        return has_support;
    }
    
    // Simple vectorized hash for demonstration
    inline uint64_t hash_key_simd(const std::string& key) {
        return std::hash<std::string>{}(key);
    }
}

// **Keep all Phase 6 Step 3 storage classes**
namespace storage {
    
class SimpleStorage {
private:
    std::unordered_map<std::string, std::string> data_;
    mutable std::shared_mutex mutex_;
    
public:
    void set(const std::string& key, const std::string& value) {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        data_[key] = value;
    }
    
    std::optional<std::string> get(const std::string& key) const {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        auto it = data_.find(key);
        return (it != data_.end()) ? std::make_optional(it->second) : std::nullopt;
    }
    
    bool del(const std::string& key) {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        return data_.erase(key) > 0;
    }
    
    void clear() {
        std::unique_lock<std::shared_mutex> lock(mutex_);
        data_.clear();
    }
    
    size_t size() const {
        std::shared_lock<std::shared_mutex> lock(mutex_);
        return data_.size();
    }
};

} // namespace storage

// **Keep Phase 6 Step 3 monitoring**
namespace monitoring {
    
struct CoreMetrics {
    std::atomic<uint64_t> requests_processed{0};
    std::atomic<uint64_t> active_connections{0};
    std::atomic<uint64_t> total_connections_accepted{0};
    std::atomic<uint64_t> pipeline_batches_processed{0};
    std::atomic<uint64_t> commands_in_pipelines{0};
    std::atomic<uint64_t> connection_migrations{0};
};

} // namespace monitoring

// **Keep Phase 6 Step 3 connection state**
struct ConnectionState {
    std::string partial_command_buffer;
    std::string response_buffer;
    std::chrono::steady_clock::time_point last_activity;
    bool has_pending_response = false;
    
    ConnectionState() : last_activity(std::chrono::steady_clock::now()) {}
};

// **Keep Phase 6 Step 3 command processor (simplified)**
class DirectOperationProcessor {
private:
    std::shared_ptr<storage::SimpleStorage> storage_;
    std::unordered_map<int, std::shared_ptr<ConnectionState>> connection_states_;
    std::mutex connection_states_mutex_;
    monitoring::CoreMetrics* metrics_;
    
public:
    explicit DirectOperationProcessor(std::shared_ptr<storage::SimpleStorage> storage, 
                                    monitoring::CoreMetrics* metrics = nullptr)
        : storage_(storage), metrics_(metrics) {}
    
    std::shared_ptr<ConnectionState> get_or_create_connection_state(int client_fd) {
        std::lock_guard<std::mutex> lock(connection_states_mutex_);
        auto& state = connection_states_[client_fd];
        if (!state) {
            state = std::make_shared<ConnectionState>();
        }
        return state;
    }
    
    void remove_connection_state(int client_fd) {
        std::lock_guard<std::mutex> lock(connection_states_mutex_);
        connection_states_.erase(client_fd);
    }
    
    // **Phase 6 Step 3 pipeline batch processing**
    void process_pipeline_batch(int client_fd, const std::vector<std::vector<std::string>>& commands) {
        auto conn_state = get_or_create_connection_state(client_fd);
        if (!conn_state) return;
        
        conn_state->response_buffer.clear();
        
        for (const auto& cmd : commands) {
            if (cmd.empty()) continue;
            
            std::string response = process_single_command(cmd);
            conn_state->response_buffer += response;
        }
        
        conn_state->has_pending_response = !conn_state->response_buffer.empty();
        
        if (metrics_) {
            metrics_->pipeline_batches_processed.fetch_add(1);
            metrics_->commands_in_pipelines.fetch_add(commands.size());
        }
    }
    
    std::string process_single_command(const std::vector<std::string>& cmd) {
        if (cmd.empty()) return "-ERR empty command\r\n";
        
        std::string command = cmd[0];
        std::transform(command.begin(), command.end(), command.begin(), ::toupper);
        
        if (command == "PING") {
            return "+PONG\r\n";
        } else if (command == "SET" && cmd.size() >= 3) {
            storage_->set(cmd[1], cmd[2]);
            return "+OK\r\n";
        } else if (command == "GET" && cmd.size() >= 2) {
            auto value = storage_->get(cmd[1]);
            if (value) {
                return "$" + std::to_string(value->length()) + "\r\n" + *value + "\r\n";
            } else {
                return "$-1\r\n";
            }
        } else if (command == "DEL" && cmd.size() >= 2) {
            bool deleted = storage_->del(cmd[1]);
            return ":" + std::to_string(deleted ? 1 : 0) + "\r\n";
        } else if (command == "FLUSHALL") {
            storage_->clear();
            return "+OK\r\n";
        } else {
            return "-ERR unknown command '" + cmd[0] + "'\r\n";
        }
    }
    
    void flush_pending_operations() {
        // Keep for compatibility
    }
};

// **PHASE 7 STEP 1: Pure io_uring CoreThread**
class IoUringCoreThread {
private:
    int core_id_;
    std::shared_ptr<storage::SimpleStorage> storage_;
    std::unique_ptr<DirectOperationProcessor> processor_;
    monitoring::CoreMetrics* metrics_;
    
    // **io_uring setup**
    struct io_uring ring_;
    static constexpr int IO_URING_QUEUE_DEPTH = 256;
    static constexpr int IO_BUFFER_SIZE = 16384;
    
    // **io_uring operation tracking**
    std::atomic<uint64_t> io_op_counter_{1};
    std::unordered_map<uint64_t, int> pending_accepts_;
    std::unordered_map<uint64_t, std::pair<int, char*>> pending_reads_;
    std::unordered_map<uint64_t, int> pending_writes_;
    std::mutex io_ops_mutex_;
    
    // **Buffer management**
    struct IoBuffer {
        char data[IO_BUFFER_SIZE];
        bool in_use{false};
    };
    std::vector<IoBuffer> io_buffers_;
    std::mutex buffer_mutex_;
    
    std::atomic<bool> running_{false};
    int server_fd_;
    
public:
    IoUringCoreThread(int core_id, std::shared_ptr<storage::SimpleStorage> storage, 
                     int server_fd, monitoring::CoreMetrics* metrics = nullptr)
        : core_id_(core_id), storage_(storage), server_fd_(server_fd), metrics_(metrics) {
        
        processor_ = std::make_unique<DirectOperationProcessor>(storage_, metrics_);
        
        // **Initialize io_uring**
        int ret = io_uring_queue_init(IO_URING_QUEUE_DEPTH, &ring_, 0);
        if (ret < 0) {
            throw std::runtime_error("Failed to initialize io_uring for core " + std::to_string(core_id_) + 
                                    ": " + std::string(strerror(-ret)));
        }
        
        // **Initialize buffer pool**
        io_buffers_.resize(IO_URING_QUEUE_DEPTH);
        for (auto& buf : io_buffers_) {
            buf.in_use = false;
        }
        
        std::cout << "✅ Core " << core_id_ << " initialized io_uring (depth=" << IO_URING_QUEUE_DEPTH 
                  << ", buffers=" << io_buffers_.size() << ")" << std::endl;
    }
    
    ~IoUringCoreThread() {
        stop();
        io_uring_queue_exit(&ring_);
    }
    
    void start() {
        running_.store(true);
        
        // **Set CPU affinity**
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(core_id_, &cpuset);
        if (sched_setaffinity(0, sizeof(cpu_set_t), &cpuset) != 0) {
            std::cerr << "❌ Failed to set CPU affinity for core " << core_id_ << std::endl;
        } else {
            std::cout << "📌 Core " << core_id_ << " CPU affinity set" << std::endl;
        }
        
        std::thread(&IoUringCoreThread::run, this).detach();
    }
    
    void stop() {
        running_.store(false);
    }
    
    void run() {
        std::cout << "🚀 Core " << core_id_ << " io_uring event loop started" << std::endl;
        
        // **Submit initial accept operations**
        submit_io_uring_accept();
        
        while (running_.load()) {
            process_io_uring_events();
            processor_->flush_pending_operations();
        }
        
        std::cout << "🛑 Core " << core_id_ << " io_uring event loop stopped" << std::endl;
    }
    
private:
    void process_io_uring_events() {
        struct __kernel_timespec ts;
        ts.tv_sec = 0;
        ts.tv_nsec = 10000000; // 10ms timeout
        
        struct io_uring_cqe *cqe;
        int ret = io_uring_wait_cqe_timeout(&ring_, &cqe, &ts);
        
        if (ret == 0) {
            // **Process all available completions in batch**
            do {
                handle_io_uring_completion(cqe);
                io_uring_cqe_seen(&ring_, cqe);
            } while (io_uring_peek_cqe(&ring_, &cqe) == 0);
        } else if (ret != -ETIME) {
            std::cerr << "❌ Core " << core_id_ << " io_uring_wait_cqe failed: " 
                      << strerror(-ret) << std::endl;
        }
        
        // **Submit any pending operations**
        io_uring_submit(&ring_);
    }
    
    void handle_io_uring_completion(struct io_uring_cqe *cqe) {
        uint64_t op_id = reinterpret_cast<uint64_t>(io_uring_cqe_get_data(cqe));
        int result = cqe->res;
        
        std::lock_guard<std::mutex> lock(io_ops_mutex_);
        
        if (pending_accepts_.count(op_id)) {
            handle_accept_completion(op_id, result);
        } else if (pending_reads_.count(op_id)) {
            handle_read_completion(op_id, result);
        } else if (pending_writes_.count(op_id)) {
            handle_write_completion(op_id, result);
        }
    }
    
    void handle_accept_completion(uint64_t op_id, int result) {
        pending_accepts_.erase(op_id);
        
        if (result > 0) {
            int client_fd = result;
            
            // **Set non-blocking**
            int flags = fcntl(client_fd, F_GETFL, 0);
            fcntl(client_fd, F_SETFL, flags | O_NONBLOCK);
            
            // **Submit read operation**
            submit_io_uring_read(client_fd);
            
            if (metrics_) {
                metrics_->total_connections_accepted.fetch_add(1);
                metrics_->active_connections.fetch_add(1);
            }
            
            std::cout << "✅ Core " << core_id_ << " accepted client (fd=" << client_fd << ") [io_uring]" << std::endl;
        }
        
        // **Submit next accept**
        submit_io_uring_accept();
    }
    
    void handle_read_completion(uint64_t op_id, int result) {
        auto it = pending_reads_.find(op_id);
        if (it == pending_reads_.end()) return;
        
        int client_fd = it->second.first;
        char* buffer = it->second.second;
        pending_reads_.erase(it);
        
        if (result > 0) {
            // **Process data using Phase 6 Step 3 pipeline processing**
            std::string data(buffer, result);
            return_buffer(buffer);
            
            // **Process client data**
            process_client_data(client_fd, data);
            
            // **Submit next read**
            submit_io_uring_read(client_fd);
            
        } else if (result == 0) {
            // **Client disconnected**
            return_buffer(buffer);
            processor_->remove_connection_state(client_fd);
            close(client_fd);
            
            if (metrics_) {
                metrics_->active_connections.fetch_sub(1);
            }
            
        } else {
            // **Error occurred**
            return_buffer(buffer);
            processor_->remove_connection_state(client_fd);
            close(client_fd);
            
            if (metrics_) {
                metrics_->active_connections.fetch_sub(1);
            }
        }
    }
    
    void handle_write_completion(uint64_t op_id, int result) {
        pending_writes_.erase(op_id);
        // **Write completion handling (minimal for now)**
    }
    
    void submit_io_uring_accept() {
        struct io_uring_sqe *sqe = io_uring_get_sqe(&ring_);
        if (!sqe) return;
        
        uint64_t op_id = io_op_counter_.fetch_add(1);
        
        io_uring_prep_accept(sqe, server_fd_, nullptr, nullptr, 0);
        io_uring_sqe_set_data(sqe, reinterpret_cast<void*>(op_id));
        
        pending_accepts_[op_id] = server_fd_;
    }
    
    void submit_io_uring_read(int client_fd) {
        struct io_uring_sqe *sqe = io_uring_get_sqe(&ring_);
        if (!sqe) return;
        
        char* buffer = get_free_buffer();
        if (!buffer) return;
        
        uint64_t op_id = io_op_counter_.fetch_add(1);
        
        io_uring_prep_recv(sqe, client_fd, buffer, IO_BUFFER_SIZE, 0);
        io_uring_sqe_set_data(sqe, reinterpret_cast<void*>(op_id));
        
        pending_reads_[op_id] = {client_fd, buffer};
    }
    
    void submit_io_uring_write(int client_fd, const std::string& data) {
        struct io_uring_sqe *sqe = io_uring_get_sqe(&ring_);
        if (!sqe) return;
        
        uint64_t op_id = io_op_counter_.fetch_add(1);
        
        io_uring_prep_send(sqe, client_fd, data.c_str(), data.length(), MSG_NOSIGNAL);
        io_uring_sqe_set_data(sqe, reinterpret_cast<void*>(op_id));
        
        pending_writes_[op_id] = client_fd;
    }
    
    char* get_free_buffer() {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        for (auto& buf : io_buffers_) {
            if (!buf.in_use) {
                buf.in_use = true;
                return buf.data;
            }
        }
        return nullptr;
    }
    
    void return_buffer(char* buffer_ptr) {
        std::lock_guard<std::mutex> lock(buffer_mutex_);
        for (auto& buf : io_buffers_) {
            if (buf.data == buffer_ptr) {
                buf.in_use = false;
                break;
            }
        }
    }
    
    void process_client_data(int client_fd, const std::string& data) {
        auto conn_state = processor_->get_or_create_connection_state(client_fd);
        if (!conn_state) return;
        
        conn_state->partial_command_buffer.append(data);
        
        // **Parse and process commands using Phase 6 Step 3 logic**
        std::vector<std::vector<std::string>> parsed_commands;
        parse_accumulated_commands(conn_state->partial_command_buffer, parsed_commands);
        
        if (!parsed_commands.empty()) {
            processor_->process_pipeline_batch(client_fd, parsed_commands);
            
            // **Send response via io_uring**
            if (conn_state->has_pending_response) {
                submit_io_uring_write(client_fd, conn_state->response_buffer);
                conn_state->has_pending_response = false;
            }
        }
    }
    
    void parse_accumulated_commands(std::string& buffer, std::vector<std::vector<std::string>>& commands) {
        size_t pos = 0;
        
        while (pos < buffer.length()) {
            if (buffer[pos] == '*') {
                // **RESP array parsing**
                size_t parsed = parse_resp_command_array(buffer, pos, commands);
                if (parsed == 0) break;
                pos += parsed;
            } else {
                // **Simple command parsing**
                size_t end = buffer.find('\n', pos);
                if (end == std::string::npos) break;
                
                std::string line = buffer.substr(pos, end - pos);
                if (!line.empty() && line.back() == '\r') {
                    line.pop_back();
                }
                
                if (!line.empty()) {
                    std::vector<std::string> cmd;
                    std::istringstream iss(line);
                    std::string word;
                    
                    while (iss >> word) {
                        cmd.push_back(word);
                    }
                    
                    if (!cmd.empty()) {
                        commands.push_back(cmd);
                    }
                }
                
                pos = end + 1;
            }
        }
        
        buffer.erase(0, pos);
    }
    
    size_t parse_resp_command_array(const std::string& buffer, size_t start, 
                                   std::vector<std::vector<std::string>>& commands) {
        size_t pos = start;
        if (pos >= buffer.length() || buffer[pos] != '*') return 0;
        pos++;
        
        size_t count_end = buffer.find('\n', pos);
        if (count_end == std::string::npos) return 0;
        
        std::string count_str = buffer.substr(pos, count_end - pos);
        if (!count_str.empty() && count_str.back() == '\r') {
            count_str.pop_back();
        }
        
        int count = std::atoi(count_str.c_str());
        if (count <= 0) return count_end - start + 1;
        
        pos = count_end + 1;
        std::vector<std::string> cmd;
        
        for (int i = 0; i < count; i++) {
            if (pos >= buffer.length() || buffer[pos] != '$') return 0;
            pos++;
            
            size_t len_end = buffer.find('\n', pos);
            if (len_end == std::string::npos) return 0;
            
            std::string len_str = buffer.substr(pos, len_end - pos);
            if (!len_str.empty() && len_str.back() == '\r') {
                len_str.pop_back();
            }
            
            int len = std::atoi(len_str.c_str());
            if (len < 0) return 0;
            
            pos = len_end + 1;
            if (pos + len + 2 > buffer.length()) return 0;
            
            std::string data = buffer.substr(pos, len);
            cmd.push_back(data);
            pos += len + 2;
        }
        
        if (!cmd.empty()) {
            commands.push_back(cmd);
        }
        
        return pos - start;
    }
};

// **Server class with io_uring cores**
class IoUringServer {
private:
    std::string host_;
    int port_;
    size_t num_cores_;
    std::shared_ptr<storage::SimpleStorage> storage_;
    std::vector<std::unique_ptr<IoUringCoreThread>> core_threads_;
    std::vector<monitoring::CoreMetrics> core_metrics_;
    std::atomic<bool> running_{false};
    int server_fd_{-1};
    
public:
    IoUringServer(const std::string& host, int port, size_t num_cores)
        : host_(host), port_(port), num_cores_(num_cores) {
        storage_ = std::make_shared<storage::SimpleStorage>();
        core_metrics_.resize(num_cores_);
    }
    
    ~IoUringServer() {
        stop();
    }
    
    bool start() {
        // **Create server socket**
        server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd_ < 0) {
            std::cerr << "❌ Failed to create socket" << std::endl;
            return false;
        }
        
        // **Set socket options**
        int opt = 1;
        setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        setsockopt(server_fd_, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
        
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port_);
        inet_pton(AF_INET, host_.c_str(), &addr.sin_addr);
        
        if (bind(server_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            std::cerr << "❌ Failed to bind to " << host_ << ":" << port_ << std::endl;
            close(server_fd_);
            return false;
        }
        
        if (listen(server_fd_, SOMAXCONN) < 0) {
            std::cerr << "❌ Failed to listen" << std::endl;
            close(server_fd_);
            return false;
        }
        
        std::cout << "✅ Server listening on " << host_ << ":" << port_ << std::endl;
        
        // **Start io_uring core threads**
        start_core_threads();
        
        running_.store(true);
        return true;
    }
    
    void stop() {
        running_.store(false);
        
        for (auto& core : core_threads_) {
            core->stop();
        }
        
        core_threads_.clear();
        
        if (server_fd_ >= 0) {
            close(server_fd_);
            server_fd_ = -1;
        }
    }
    
    void run() {
        std::cout << "🚀 io_uring server running with " << num_cores_ << " cores" << std::endl;
        
        while (running_.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(5));
            print_statistics();
        }
    }
    
private:
    void start_core_threads() {
        core_threads_.reserve(num_cores_);
        
        for (size_t i = 0; i < num_cores_; ++i) {
            auto core = std::make_unique<IoUringCoreThread>(
                i, storage_, server_fd_, &core_metrics_[i]);
            
            core->start();
            core_threads_.push_back(std::move(core));
        }
        
        std::cout << "✅ Started " << num_cores_ << " io_uring core threads" << std::endl;
    }
    
    void print_statistics() {
        uint64_t total_requests = 0;
        uint64_t total_connections = 0;
        uint64_t total_pipelines = 0;
        
        for (const auto& metrics : core_metrics_) {
            total_requests += metrics.requests_processed.load();
            total_connections += metrics.active_connections.load();
            total_pipelines += metrics.pipeline_batches_processed.load();
        }
        
        std::cout << "📊 Stats: " << total_requests << " requests, " 
                  << total_connections << " connections, " 
                  << total_pipelines << " pipelines" << std::endl;
    }
};

} // namespace meteor

// **Signal handler**
std::atomic<bool> shutdown_requested{false};

void signal_handler(int signal) {
    std::cout << "\n🛑 Shutdown requested (signal " << signal << ")" << std::endl;
    shutdown_requested.store(true);
}

int main(int argc, char* argv[]) {
    std::string host = "127.0.0.1";
    int port = 6379;
    size_t num_cores = std::thread::hardware_concurrency();
    
    // **Parse command line arguments**
    int opt;
    while ((opt = getopt(argc, argv, "h:p:c:")) != -1) {
        switch (opt) {
            case 'h':
                host = optarg;
                break;
            case 'p':
                port = std::atoi(optarg);
                break;
            case 'c':
                num_cores = std::atoi(optarg);
                break;
            default:
                std::cout << "Usage: " << argv[0] << " [-h host] [-p port] [-c cores]" << std::endl;
                return 1;
        }
    }
    
    // **Setup signal handling**
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    std::cout << "🚀 METEOR PHASE 7 STEP 1: CLEAN io_uring Server" << std::endl;
    std::cout << "🎯 Target: Beat DragonflyDB performance (1.5M+ RPS)" << std::endl;
    std::cout << "⚡ Architecture: Pure io_uring + Phase 6 Step 3 optimizations" << std::endl;
    std::cout << "🏗️  Config: " << num_cores << " cores, " << host << ":" << port << std::endl;
    std::cout << "" << std::endl;
    
    try {
        meteor::IoUringServer server(host, port, num_cores);
        
        if (!server.start()) {
            std::cerr << "❌ Failed to start server" << std::endl;
            return 1;
        }
        
        // **Run until shutdown**
        while (!shutdown_requested.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        
        server.stop();
        
    } catch (const std::exception& e) {
        std::cerr << "❌ Server error: " << e.what() << std::endl;
        return 1;
    }
    
    std::cout << "✅ Server shutdown complete" << std::endl;
    return 0;
}