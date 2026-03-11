/**
 * SIMPLE QUEUE APPROACH - Temporal Coherence Server
 * 
 * PHILOSOPHY: Keep it simple, get it working, optimize later
 * 
 * APPROACH:
 * 1. Use simple std::vector to store commands in sequence
 * 2. Process commands one by one and store responses
 * 3. Combine responses in original order
 * 4. Add conflict detection and batching later once baseline works
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

// **SIMPLE CACHE**: Basic in-memory cache
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

// **SIMPLE COMMAND**: Basic command structure
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

// **SIMPLE RESPONSE**: Basic response structure
struct SimpleResponse {
    std::string data;
    uint32_t sequence_id;
    bool success;
    
    SimpleResponse(const std::string& d, uint32_t seq, bool succ) 
        : data(d), sequence_id(seq), success(succ) {}
};

// **SIMPLE QUEUE PROCESSOR**: Core processing logic
class SimpleQueueProcessor {
private:
    std::shared_ptr<SimpleCache> cache_;
    uint32_t core_id_;
    uint32_t total_cores_;
    std::atomic<uint64_t> commands_processed_{0};
    
public:
    SimpleQueueProcessor(uint32_t core_id, uint32_t total_cores) 
        : core_id_(core_id), total_cores_(total_cores) {
        cache_ = std::make_shared<SimpleCache>();
    }
    
    // **SIMPLE COMMAND EXECUTION**: Basic Redis command processing
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
    
    // **SIMPLE PIPELINE PROCESSING**: Process command queue and return ordered responses
    std::string process_pipeline_simple(const std::vector<SimpleCommand>& commands) {
        std::vector<SimpleResponse> responses;
        responses.reserve(commands.size());
        
        // **STEP 1**: Process all commands sequentially (simple approach)
        for (const auto& cmd : commands) {
            responses.push_back(execute_command(cmd));
        }
        
        // **STEP 2**: Combine responses in original sequence order
        std::string combined_response;
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

// **SIMPLE SERVER**: Basic multi-core server
class SimpleQueueServer {
private:
    uint32_t num_cores_;
    uint32_t base_port_;
    std::vector<std::unique_ptr<SimpleQueueProcessor>> processors_;
    std::vector<std::thread> core_threads_;
    std::atomic<bool> running_{false};
    
    // **SERVER SOCKETS**: One per core
    std::vector<int> server_sockets_;
    
public:
    SimpleQueueServer(uint32_t cores, uint32_t base_port) 
        : num_cores_(cores), base_port_(base_port) {
        
        // **INITIALIZE PROCESSORS**: One per core
        for (uint32_t i = 0; i < num_cores_; ++i) {
            processors_.push_back(std::make_unique<SimpleQueueProcessor>(i, num_cores_));
        }
        
        server_sockets_.resize(num_cores_, -1);
    }
    
    // **RESP PARSING**: Simple RESP command parsing
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
    
    // **SIMPLE COMMAND PARSER**: Parse single RESP command
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
    
    // **KEY ROUTING**: Simple hash-based routing to cores
    uint32_t route_key_to_core(const std::string& key) {
        if (key.empty()) return 0;
        
        std::hash<std::string> hasher;
        return hasher(key) % num_cores_;
    }
    
    // **SIMPLE PIPELINE HANDLER**: Process pipeline with simple queues
    void handle_pipeline_simple(int client_fd, const std::string& data, uint32_t core_id) {
        // **PARSE COMMANDS**: Get all commands from pipeline
        std::vector<std::string> raw_commands = parse_resp_commands(data);
        std::vector<SimpleCommand> command_queue;
        
        uint32_t sequence_id = 0;
        
        // **BUILD COMMAND QUEUE**: Parse and route each command
        for (const auto& raw_cmd : raw_commands) {
            auto parsed = parse_single_command(raw_cmd);
            if (!parsed.empty()) {
                std::string operation = parsed[0];
                std::string key = parsed.size() > 1 ? parsed[1] : "";
                std::string value = parsed.size() > 2 ? parsed[2] : "";
                
                // **SIMPLE ROUTING**: Determine target core
                uint32_t target_core = route_key_to_core(key);
                
                command_queue.emplace_back(operation, key, value, sequence_id++, target_core);
            }
        }
        
        if (command_queue.empty()) {
            return;
        }
        
        // **SIMPLE PROCESSING**: For now, process all commands locally
        // TODO: Add cross-core routing later
        std::string response = processors_[core_id]->process_pipeline_simple(command_queue);
        
        // **SEND RESPONSE**: Simple socket send
        if (!response.empty()) {
            send(client_fd, response.c_str(), response.length(), MSG_NOSIGNAL);
        }
    }
    
    // **CORE THREAD**: Handle connections for one core
    void run_core_thread(uint32_t core_id) {
        int server_fd = server_sockets_[core_id];
        int port = base_port_ + core_id;
        
        std::cout << "✅ Core " << core_id << " thread started (port " << port << ")" << std::endl;
        
        // **SIMPLE EVENT LOOP**: Basic epoll for this core
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
            int nfds = epoll_wait(epoll_fd, events, 32, 100); // 100ms timeout
            
            for (int i = 0; i < nfds; ++i) {
                if (events[i].data.fd == server_fd) {
                    // **ACCEPT CONNECTION**
                    sockaddr_in client_addr;
                    socklen_t client_len = sizeof(client_addr);
                    int client_fd = accept(server_fd, (sockaddr*)&client_addr, &client_len);
                    
                    if (client_fd >= 0) {
                        ev.events = EPOLLIN;
                        ev.data.fd = client_fd;
                        epoll_ctl(epoll_fd, EPOLL_CTL_ADD, client_fd, &ev);
                    }
                    
                } else {
                    // **HANDLE CLIENT DATA**
                    int client_fd = events[i].data.fd;
                    char buffer[4096];
                    
                    ssize_t bytes_read = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
                    if (bytes_read > 0) {
                        buffer[bytes_read] = '\0';
                        std::string data(buffer, bytes_read);
                        
                        // **PROCESS PIPELINE**
                        handle_pipeline_simple(client_fd, data, core_id);
                        
                    } else if (bytes_read == 0) {
                        // **CLIENT DISCONNECTED**
                        epoll_ctl(epoll_fd, EPOLL_CTL_DEL, client_fd, nullptr);
                        close(client_fd);
                    }
                }
            }
        }
        
        close(epoll_fd);
        std::cout << "✅ Core " << core_id << " thread stopped" << std::endl;
    }
    
    // **START SERVER**: Initialize and start all cores
    bool start() {
        running_.store(true);
        
        std::cout << "🚀 STARTING SIMPLE QUEUE SERVER" << std::endl;
        std::cout << "===============================" << std::endl;
        std::cout << "Cores: " << num_cores_ << std::endl;
        std::cout << "Base port: " << base_port_ << std::endl;
        std::cout << "Ports: " << base_port_ << "-" << (base_port_ + num_cores_ - 1) << std::endl;
        std::cout << "" << std::endl;
        
        // **CREATE SERVER SOCKETS**: One per core
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
            std::cout << "✅ Core " << core_id << " listening on port " << port << std::endl;
        }
        
        std::cout << "" << std::endl;
        
        // **START CORE THREADS**: One thread per core
        for (uint32_t core_id = 0; core_id < num_cores_; ++core_id) {
            core_threads_.emplace_back(&SimpleQueueServer::run_core_thread, this, core_id);
        }
        
        std::cout << "🎯 SIMPLE QUEUE SERVER OPERATIONAL!" << std::endl;
        std::cout << "====================================" << std::endl;
        std::cout << "Architecture: Simple queue-based processing" << std::endl;
        std::cout << "Command flow: Queue → Process → Combine → Response" << std::endl;
        std::cout << "Cross-core routing: Basic hash-based (TODO: enhance)" << std::endl;
        std::cout << "Conflict detection: Not yet implemented (TODO)" << std::endl;
        std::cout << "" << std::endl;
        std::cout << "Ready for testing with memtier_benchmark!" << std::endl;
        
        return true;
    }
    
    // **STOP SERVER**: Graceful shutdown
    void stop() {
        std::cout << "\n🛑 Stopping simple queue server..." << std::endl;
        
        running_.store(false);
        
        // **JOIN THREADS**
        for (auto& thread : core_threads_) {
            if (thread.joinable()) {
                thread.join();
            }
        }
        
        // **CLOSE SOCKETS**
        for (int fd : server_sockets_) {
            if (fd >= 0) {
                close(fd);
            }
        }
        
        // **SHOW STATS**
        std::cout << "\n📊 Final Statistics:" << std::endl;
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
        std::cout << "✅ Server stopped gracefully" << std::endl;
    }
    
    // **STATS DISPLAY**: Periodic stats (for testing)
    void display_stats() {
        uint64_t total_commands = 0;
        for (const auto& processor : processors_) {
            total_commands += processor->get_commands_processed();
        }
        
        std::cout << "📊 Commands processed: " << total_commands << std::endl;
    }
};

// **MAIN**: Server entry point
int main(int argc, char* argv[]) {
    uint32_t num_cores = 4;
    uint32_t base_port = 6379;
    
    // **PARSE ARGUMENTS**: Simple argument parsing
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            num_cores = std::stoi(argv[i + 1]);
            ++i;
        } else if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            base_port = std::stoi(argv[i + 1]);
            ++i;
        }
    }
    
    std::cout << "🎯 SIMPLE QUEUE TEMPORAL COHERENCE SERVER" << std::endl;
    std::cout << "=========================================" << std::endl;
    std::cout << "Approach: Keep it simple, get it working" << std::endl;
    std::cout << "Architecture: Simple queues + sequential processing" << std::endl;
    std::cout << "" << std::endl;
    
    SimpleQueueServer server(num_cores, base_port);
    
    if (!server.start()) {
        std::cerr << "❌ Failed to start server" << std::endl;
        return 1;
    }
    
    // **STATS THREAD**: Simple periodic stats display
    std::atomic<bool> stats_running{true};
    std::thread stats_thread([&server, &stats_running]() {
        while (stats_running.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(10));
            if (stats_running.load()) {
                server.display_stats();
            }
        }
    });
    
    // **WAIT FOR SIGNAL**: Simple signal handling
    std::cout << "\n⏳ Server running. Press Ctrl+C to stop...\n" << std::endl;
    
    // **SIMPLE WAIT LOOP**: Just sleep and periodically check
    while (true) {
        std::this_thread::sleep_for(std::chrono::seconds(5));
        // Server threads continue running in background
        // In production, we'd wait for SIGINT/SIGTERM signals here
    }
    
    stats_running.store(false);
    if (stats_thread.joinable()) {
        stats_thread.join();
    }
    
    server.stop();
    
    return 0;
}
