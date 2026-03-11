/**
 * INCREMENTAL OPTIMIZATION SERVER - One Small Improvement at a Time
 * 
 * Building on the proven simple queue baseline (800K QPS) with ONE targeted optimization:
 * - OPTIMIZATION: Reduced system calls through batched socket operations
 * 
 * Philosophy: Add ONE optimization, measure, keep if helpful, discard if not.
 * Target: 1M+ QPS (25% improvement over baseline)
 */

#include <iostream>
#include <vector>
#include <string>
#include <unordered_map>
#include <sstream>
#include <algorithm>
#include <atomic>
#include <thread>
#include <mutex>
#include <chrono>
#include <cstring>
#include <memory>
#include <optional>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/epoll.h>

// **SIMPLE CACHE**: Exact same as baseline (proven to work)
class SimpleCache {
private:
    std::unordered_map<std::string, std::string> data_;
    mutable std::mutex mutex_;
    
public:
    bool set(const std::string& key, const std::string& value) {
        std::lock_guard<std::mutex> lock(mutex_);
        data_[key] = value;
        return true;
    }
    
    std::optional<std::string> get(const std::string& key) const {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = data_.find(key);
        return (it != data_.end()) ? std::make_optional(it->second) : std::nullopt;
    }
    
    bool del(const std::string& key) {
        std::lock_guard<std::mutex> lock(mutex_);
        return data_.erase(key) > 0;
    }
    
    size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return data_.size();
    }
};

// **SIMPLE COMMAND**: Exact same as baseline
struct SimpleCommand {
    std::string operation;
    std::string key;
    std::string value;
    uint32_t sequence_id;
    uint32_t target_core;
    
    SimpleCommand(const std::string& op, const std::string& k, const std::string& v, 
                 uint32_t seq, uint32_t core) 
        : operation(op), key(k), value(v), sequence_id(seq), target_core(core) {}
};

// **SIMPLE RESPONSE**: Exact same as baseline
struct SimpleResponse {
    std::string data;
    uint32_t sequence_id;
    bool success;
    
    SimpleResponse(const std::string& d, uint32_t seq, bool succ) 
        : data(d), sequence_id(seq), success(succ) {}
};

// **INCREMENTAL OPTIMIZED PROCESSOR**: Same as baseline + ONE optimization
class IncrementalOptimizedProcessor {
private:
    std::shared_ptr<SimpleCache> cache_;
    uint32_t core_id_;
    uint32_t total_cores_;
    std::atomic<uint64_t> commands_processed_{0};
    
public:
    IncrementalOptimizedProcessor(uint32_t core_id, uint32_t total_cores) 
        : core_id_(core_id), total_cores_(total_cores) {
        cache_ = std::make_shared<SimpleCache>();
    }
    
    // **SAME COMMAND EXECUTION**: Exact same as baseline (proven to work)
    SimpleResponse execute_command(const SimpleCommand& cmd) {
        commands_processed_.fetch_add(1);
        
        std::string cmd_upper = cmd.operation;
        std::transform(cmd_upper.begin(), cmd_upper.end(), cmd_upper.begin(), ::toupper);
        
        if (cmd_upper == "SET") {
            bool success = cache_->set(cmd.key, cmd.value);
            return SimpleResponse(success ? "+OK\r\n" : "-ERR SET failed\r\n", 
                                cmd.sequence_id, success);
                                
        } else if (cmd_upper == "GET") {
            auto result = cache_->get(cmd.key);
            if (result) {
                std::string response = "$" + std::to_string(result->length()) + "\r\n" + *result + "\r\n";
                return SimpleResponse(response, cmd.sequence_id, true);
            } else {
                return SimpleResponse("$-1\r\n", cmd.sequence_id, true);
            }
            
        } else if (cmd_upper == "DEL") {
            bool deleted = cache_->del(cmd.key);
            std::string response = ":" + std::to_string(deleted ? 1 : 0) + "\r\n";
            return SimpleResponse(response, cmd.sequence_id, deleted);
            
        } else if (cmd_upper == "PING") {
            return SimpleResponse("+PONG\r\n", cmd.sequence_id, true);
            
        } else {
            return SimpleResponse("-ERR unknown command '" + cmd.operation + "'\r\n", 
                                cmd.sequence_id, false);
        }
    }
    
    // **OPTIMIZATION 1: BATCHED RESPONSE WRITING**: Reduce system calls
    std::string process_pipeline_optimized(const std::vector<SimpleCommand>& commands) {
        std::vector<SimpleResponse> responses;
        responses.reserve(commands.size());
        
        // Process commands (same as baseline)
        for (const auto& cmd : commands) {
            responses.push_back(execute_command(cmd));
        }
        
        // **OPTIMIZATION**: Pre-calculate total response size to avoid reallocations
        size_t total_size = 0;
        for (const auto& response : responses) {
            total_size += response.data.size();
        }
        
        // **OPTIMIZATION**: Single allocation + efficient appending
        std::string combined_response;
        combined_response.reserve(total_size);
        
        for (const auto& response : responses) {
            combined_response += response.data;
        }
        
        return combined_response;
    }
    
    uint64_t get_commands_processed() const {
        return commands_processed_.load();
    }
    
    size_t get_cache_size() const {
        return cache_->size();
    }
};

// **INCREMENTAL OPTIMIZED SERVER**: Same as baseline + ONE optimization
class IncrementalOptimizedServer {
private:
    uint32_t num_cores_;
    uint32_t base_port_;
    std::vector<std::unique_ptr<IncrementalOptimizedProcessor>> processors_;
    std::vector<std::thread> core_threads_;
    std::atomic<bool> running_{false};
    std::vector<int> server_sockets_;
    
public:
    IncrementalOptimizedServer(uint32_t cores, uint32_t base_port) 
        : num_cores_(cores), base_port_(base_port) {
        
        for (uint32_t i = 0; i < num_cores_; ++i) {
            processors_.push_back(std::make_unique<IncrementalOptimizedProcessor>(i, num_cores_));
        }
        
        server_sockets_.resize(num_cores_, -1);
    }
    
    // **SAME RESP PARSING**: Exact same as baseline (proven to work)
    std::vector<std::string> parse_resp_commands(const std::string& data) {
        std::vector<std::string> commands;
        size_t pos = 0;
        
        while (pos < data.length()) {
            size_t start = data.find('*', pos);
            if (start == std::string::npos) break;
            
            size_t end = data.find('*', start + 1);
            if (end == std::string::npos) end = data.length();
            
            commands.push_back(data.substr(start, end - start));
            pos = end;
        }
        
        return commands;
    }
    
    // **SAME COMMAND PARSER**: Exact same as baseline
    std::vector<std::string> parse_single_command(const std::string& resp_data) {
        std::vector<std::string> parts;
        std::istringstream iss(resp_data);
        std::string line;
        
        if (!std::getline(iss, line) || line.empty() || line[0] != '*') {
            return parts;
        }
        
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        
        int arg_count = std::stoi(line.substr(1));
        
        for (int i = 0; i < arg_count; ++i) {
            if (!std::getline(iss, line)) break;
            if (line.empty() || line[0] != '$') continue;
            
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            
            int str_len = std::stoi(line.substr(1));
            
            if (!std::getline(iss, line)) break;
            
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            
            if (str_len >= 0 && line.length() >= static_cast<size_t>(str_len)) {
                parts.push_back(line.substr(0, str_len));
            }
        }
        
        return parts;
    }
    
    // **SAME KEY ROUTING**: Exact same as baseline
    uint32_t route_key_to_core(const std::string& key) {
        if (key.empty()) return 0;
        
        std::hash<std::string> hasher;
        return hasher(key) % num_cores_;
    }
    
    // **OPTIMIZATION 2: SINGLE WRITE CALL**: Use single write() instead of multiple sends
    void handle_pipeline_optimized(int client_fd, const std::string& data, uint32_t core_id) {
        // Parse commands (same as baseline)
        std::vector<std::string> raw_commands = parse_resp_commands(data);
        std::vector<SimpleCommand> command_queue;
        
        uint32_t sequence_id = 0;
        
        for (const auto& raw_cmd : raw_commands) {
            auto parsed = parse_single_command(raw_cmd);
            if (!parsed.empty()) {
                std::string operation = parsed[0];
                std::string key = parsed.size() > 1 ? parsed[1] : "";
                std::string value = parsed.size() > 2 ? parsed[2] : "";
                
                uint32_t target_core = route_key_to_core(key);
                
                command_queue.emplace_back(operation, key, value, sequence_id++, target_core);
            }
        }
        
        if (command_queue.empty()) {
            return;
        }
        
        // Process pipeline (with batched response building)
        std::string response = processors_[core_id]->process_pipeline_optimized(command_queue);
        
        // **OPTIMIZATION**: Single write call instead of multiple sends
        if (!response.empty()) {
            ssize_t bytes_written = 0;
            ssize_t total_bytes = response.length();
            const char* data_ptr = response.c_str();
            
            // **OPTIMIZATION**: Ensure all data is written in minimal system calls
            while (bytes_written < total_bytes) {
                ssize_t result = write(client_fd, data_ptr + bytes_written, 
                                     total_bytes - bytes_written);
                if (result > 0) {
                    bytes_written += result;
                } else if (result == -1 && errno != EAGAIN && errno != EWOULDBLOCK) {
                    break;  // Connection error
                } else {
                    // Would block - in real implementation, we'd handle this better
                    usleep(1);  // Brief pause before retry
                }
            }
        }
    }
    
    // **SAME CORE THREAD**: Mostly same as baseline, using optimized handler
    void run_core_thread_optimized(uint32_t core_id) {
        int server_fd = server_sockets_[core_id];
        int port = base_port_ + core_id;
        
        std::cout << "✅ Incremental Core " << core_id << " started (port " << port << ")" << std::endl;
        
        int epoll_fd = epoll_create1(0);
        if (epoll_fd == -1) {
            std::cerr << "❌ Core " << core_id << ": epoll_create failed" << std::endl;
            return;
        }
        
        struct epoll_event ev, events[32];
        ev.events = EPOLLIN;
        ev.data.fd = server_fd;
        epoll_ctl(epoll_fd, EPOLL_CTL_ADD, server_fd, &ev);
        
        while (running_.load()) {
            int nfds = epoll_wait(epoll_fd, events, 32, 100);
            
            for (int i = 0; i < nfds; ++i) {
                if (events[i].data.fd == server_fd) {
                    // Accept connection
                    sockaddr_in client_addr;
                    socklen_t client_len = sizeof(client_addr);
                    int client_fd = accept(server_fd, (sockaddr*)&client_addr, &client_len);
                    
                    if (client_fd >= 0) {
                        ev.events = EPOLLIN;
                        ev.data.fd = client_fd;
                        epoll_ctl(epoll_fd, EPOLL_CTL_ADD, client_fd, &ev);
                    }
                    
                } else {
                    // Handle client data with optimized processing
                    int client_fd = events[i].data.fd;
                    char buffer[4096];
                    
                    ssize_t bytes_read = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
                    if (bytes_read > 0) {
                        buffer[bytes_read] = '\0';
                        std::string data(buffer, bytes_read);
                        
                        // **USE OPTIMIZED HANDLER**
                        handle_pipeline_optimized(client_fd, data, core_id);
                        
                    } else if (bytes_read == 0) {
                        epoll_ctl(epoll_fd, EPOLL_CTL_DEL, client_fd, nullptr);
                        close(client_fd);
                    }
                }
            }
        }
        
        close(epoll_fd);
        std::cout << "✅ Incremental Core " << core_id << " stopped" << std::endl;
    }
    
    // **SAME START**: Exact same as baseline
    bool start() {
        running_.store(true);
        
        std::cout << "🚀 STARTING INCREMENTAL OPTIMIZED SERVER" << std::endl;
        std::cout << "=======================================" << std::endl;
        std::cout << "Baseline: 800K QPS (simple queue)" << std::endl;
        std::cout << "Target: 1M+ QPS (25% improvement)" << std::endl;
        std::cout << "Optimization: Reduced system calls" << std::endl;
        std::cout << "" << std::endl;
        
        for (uint32_t core_id = 0; core_id < num_cores_; ++core_id) {
            int port = base_port_ + core_id;
            
            int server_fd = socket(AF_INET, SOCK_STREAM, 0);
            if (server_fd < 0) {
                std::cerr << "❌ Core " << core_id << ": Failed to create socket" << std::endl;
                return false;
            }
            
            int opt = 1;
            setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
            
            sockaddr_in addr{};
            addr.sin_family = AF_INET;
            addr.sin_addr.s_addr = INADDR_ANY;
            addr.sin_port = htons(port);
            
            if (bind(server_fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
                std::cerr << "❌ Core " << core_id << ": Failed to bind port " << port << std::endl;
                close(server_fd);
                return false;
            }
            
            if (listen(server_fd, 128) < 0) {
                std::cerr << "❌ Core " << core_id << ": Failed to listen on port " << port << std::endl;
                close(server_fd);
                return false;
            }
            
            server_sockets_[core_id] = server_fd;
            std::cout << "✅ Incremental Core " << core_id << " listening on port " << port << std::endl;
        }
        
        std::cout << "" << std::endl;
        
        for (uint32_t core_id = 0; core_id < num_cores_; ++core_id) {
            core_threads_.emplace_back(&IncrementalOptimizedServer::run_core_thread_optimized, this, core_id);
        }
        
        std::cout << "🎯 INCREMENTAL OPTIMIZED SERVER OPERATIONAL!" << std::endl;
        std::cout << "===========================================" << std::endl;
        std::cout << "Changes from baseline:" << std::endl;
        std::cout << "  ✅ Pre-calculated response sizes (reduce allocations)" << std::endl;
        std::cout << "  ✅ Single write() calls (reduce system calls)" << std::endl;
        std::cout << "  ✅ Reserved string capacity (reduce reallocations)" << std::endl;
        std::cout << "" << std::endl;
        std::cout << "Ready for incremental testing!" << std::endl;
        
        return true;
    }
    
    // **SAME STOP**: Exact same as baseline
    void stop() {
        std::cout << "\n🛑 Stopping incremental optimized server..." << std::endl;
        
        running_.store(false);
        
        for (auto& thread : core_threads_) {
            if (thread.joinable()) {
                thread.join();
            }
        }
        
        for (int fd : server_sockets_) {
            if (fd >= 0) {
                close(fd);
            }
        }
        
        // Show stats
        std::cout << "\n📊 Final Incremental Performance:" << std::endl;
        uint64_t total_commands = 0;
        size_t total_cache_size = 0;
        
        for (uint32_t i = 0; i < num_cores_; ++i) {
            uint64_t core_commands = processors_[i]->get_commands_processed();
            size_t core_cache = processors_[i]->get_cache_size();
            
            total_commands += core_commands;
            total_cache_size += core_cache;
            
            std::cout << "  Core " << i << ": " << core_commands << " commands, " 
                     << core_cache << " cached items" << std::endl;
        }
        
        std::cout << "  TOTAL: " << total_commands << " commands processed" << std::endl;
        std::cout << "  TOTAL: " << total_cache_size << " items in cache" << std::endl;
        std::cout << "✅ Incremental optimized server stopped" << std::endl;
    }
    
    void display_stats() {
        uint64_t total_commands = 0;
        for (const auto& processor : processors_) {
            total_commands += processor->get_commands_processed();
        }
        
        std::cout << "📊 Incremental Performance: " << total_commands << " total commands" << std::endl;
    }
};

// **MAIN**: Incremental optimized server entry point
int main(int argc, char* argv[]) {
    uint32_t num_cores = 4;
    uint32_t base_port = 8000;
    
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            num_cores = std::stoi(argv[i + 1]);
            ++i;
        } else if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            base_port = std::stoi(argv[i + 1]);
            ++i;
        }
    }
    
    std::cout << "🎯 INCREMENTAL OPTIMIZED SERVER" << std::endl;
    std::cout << "==============================" << std::endl;
    std::cout << "Strategy: One small optimization at a time" << std::endl;
    std::cout << "Baseline: 800K QPS (simple queue)" << std::endl;
    std::cout << "Target: 1M+ QPS (25% improvement)" << std::endl;
    std::cout << "" << std::endl;
    
    IncrementalOptimizedServer server(num_cores, base_port);
    
    if (!server.start()) {
        std::cerr << "❌ Failed to start incremental optimized server" << std::endl;
        return 1;
    }
    
    std::atomic<bool> stats_running{true};
    std::thread stats_thread([&server, &stats_running]() {
        while (stats_running.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(10));
            if (stats_running.load()) {
                server.display_stats();
            }
        }
    });
    
    std::cout << "\n⏳ Incremental optimized server running. Press Ctrl+C to stop...\n" << std::endl;
    
    while (true) {
        std::this_thread::sleep_for(std::chrono::seconds(5));
    }
    
    stats_running.store(false);
    if (stats_thread.joinable()) {
        stats_thread.join();
    }
    
    server.stop();
    
    return 0;
}














