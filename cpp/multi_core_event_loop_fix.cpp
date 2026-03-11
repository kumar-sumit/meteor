// **IMMEDIATE FIX: Multi-Core Event Loop Architecture**
// Addresses the single-threaded event loop bottleneck

#include <thread>
#include <vector>
#include <atomic>
#include <memory>
#include <sched.h>
#include <pthread.h>

namespace meteor {
namespace network {

class MultiCoreEventServer {
private:
    struct CoreEventLoop {
        int core_id;
        std::unique_ptr<std::thread> thread;
        std::unique_ptr<network::EpollEventLoop> event_loop;
        std::atomic<uint64_t> connections_count{0};
        std::atomic<uint64_t> requests_processed{0};
        
        CoreEventLoop(int id) : core_id(id) {
            event_loop = std::make_unique<network::EpollEventLoop>();
        }
    };
    
    std::vector<std::unique_ptr<CoreEventLoop>> core_loops_;
    std::atomic<size_t> connection_distributor_{0};
    std::atomic<bool> running_{false};
    int server_fd_;
    size_t num_cores_;
    
    // Pin thread to specific CPU core
    void pin_thread_to_core(int core_id) {
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);
        CPU_SET(core_id, &cpuset);
        
        if (pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset) != 0) {
            std::cerr << "Warning: Failed to pin thread to core " << core_id << std::endl;
        }
    }
    
    // Core-specific event loop
    void core_event_loop(int core_id) {
        pin_thread_to_core(core_id);
        
        auto& core_loop = core_loops_[core_id];
        
        std::cout << "🔥 Core " << core_id << " event loop started" << std::endl;
        
        while (running_.load()) {
            int num_events = core_loop->event_loop->wait_events(50); // Shorter timeout
            
            if (num_events <= 0) continue;
            
            auto& events = core_loop->event_loop->get_events();
            
            for (int i = 0; i < num_events; ++i) {
                int fd = events[i].data.fd;
                uint32_t event_mask = events[i].events;
                
                // Handle client events (server_fd is handled separately)
                if (event_mask & EPOLLIN) {
                    if (!handle_read_on_core(fd, core_id)) {
                        core_loop->event_loop->remove_socket(fd);
                        core_loop->connections_count.fetch_sub(1);
                    } else {
                        core_loop->requests_processed.fetch_add(1);
                    }
                }
                
                if (event_mask & EPOLLOUT) {
                    handle_write_on_core(fd, core_id);
                }
                
                if (event_mask & (EPOLLHUP | EPOLLERR)) {
                    core_loop->event_loop->remove_socket(fd);
                    core_loop->connections_count.fetch_sub(1);
                }
            }
        }
        
        std::cout << "🔥 Core " << core_id << " processed " 
                  << core_loop->requests_processed.load() << " requests" << std::endl;
    }
    
    bool handle_read_on_core(int client_fd, int core_id) {
        // Core-specific request handling
        auto conn = core_loops_[core_id]->event_loop->get_connection(client_fd);
        if (!conn) return false;
        
        char buffer[8192];  // Larger buffer for better performance
        ssize_t bytes_read = recv(client_fd, buffer, sizeof(buffer) - 1, MSG_DONTWAIT);
        
        if (bytes_read <= 0) {
            if (bytes_read == 0 || (errno != EAGAIN && errno != EWOULDBLOCK)) {
                return false;
            }
            return true;
        }
        
        buffer[bytes_read] = '\0';
        conn->read_buffer += buffer;
        conn->last_activity = std::chrono::steady_clock::now();
        
        // Process commands on this core
        return process_commands_on_core(conn, core_id);
    }
    
    bool process_commands_on_core(std::shared_ptr<ConnectionState> conn, int core_id) {
        size_t pos = 0;
        while (pos < conn->read_buffer.size()) {
            auto cmd_result = parser_.parse_command(conn->read_buffer, pos);
            if (!cmd_result.has_value()) break;
            
            auto& cmd = cmd_result.value();
            
            // **KEY INSIGHT**: Route based on key hash to maintain data locality
            if (!cmd.args.empty()) {
                size_t key_hash = hash::fast_hash(cmd.args[0]);
                size_t target_core = key_hash % num_cores_;
                
                if (target_core == core_id) {
                    // Process locally - optimal case
                    std::string response = process_command_locally(cmd, core_id);
                    conn->write_buffer += response;
                } else {
                    // Cross-core request - needs optimization
                    std::string response = process_command_cross_core(cmd, target_core);
                    conn->write_buffer += response;
                }
            }
        }
        
        conn->read_buffer.erase(0, pos);
        
        // Schedule write if needed
        if (!conn->write_buffer.empty()) {
            core_loops_[core_id]->event_loop->modify_socket(conn->fd, EPOLLIN | EPOLLOUT | EPOLLET);
        }
        
        return true;
    }
    
    void handle_write_on_core(int client_fd, int core_id) {
        auto conn = core_loops_[core_id]->event_loop->get_connection(client_fd);
        if (!conn || conn->write_buffer.empty()) return;
        
        ssize_t bytes_sent = send(client_fd, conn->write_buffer.c_str(), 
                                 conn->write_buffer.size(), MSG_DONTWAIT | MSG_NOSIGNAL);
        
        if (bytes_sent > 0) {
            conn->write_buffer.erase(0, bytes_sent);
            if (conn->write_buffer.empty()) {
                core_loops_[core_id]->event_loop->modify_socket(client_fd, EPOLLIN | EPOLLET);
            }
        }
    }
    
public:
    MultiCoreEventServer(int server_fd, size_t num_cores = 0) 
        : server_fd_(server_fd) {
        
        if (num_cores == 0) {
            num_cores_ = std::thread::hardware_concurrency();
        } else {
            num_cores_ = num_cores;
        }
        
        std::cout << "🚀 Initializing Multi-Core Event Server with " 
                  << num_cores_ << " cores" << std::endl;
        
        // Create core event loops
        for (size_t i = 0; i < num_cores_; ++i) {
            core_loops_.push_back(std::make_unique<CoreEventLoop>(i));
        }
    }
    
    void start() {
        running_.store(true);
        
        // Start core event loops
        for (size_t i = 0; i < num_cores_; ++i) {
            core_loops_[i]->thread = std::make_unique<std::thread>(
                &MultiCoreEventServer::core_event_loop, this, i);
        }
        
        std::cout << "✅ All " << num_cores_ << " core event loops started" << std::endl;
        
        // Main accept loop (single thread for connection distribution)
        accept_and_distribute();
    }
    
    void accept_and_distribute() {
        std::cout << "🔄 Starting connection distribution loop" << std::endl;
        
        while (running_.load()) {
            struct sockaddr_in client_addr;
            socklen_t client_len = sizeof(client_addr);
            
            int client_fd = accept(server_fd_, (struct sockaddr*)&client_addr, &client_len);
            if (client_fd < 0) {
                if (running_.load()) {
                    std::this_thread::sleep_for(std::chrono::microseconds(100));
                }
                continue;
            }
            
            // Configure socket
            network::SocketUtils::set_non_blocking(client_fd);
            network::SocketUtils::set_tcp_nodelay(client_fd);
            
            // **LOAD BALANCING**: Distribute to least loaded core
            size_t target_core = find_least_loaded_core();
            
            // Add to target core's event loop
            core_loops_[target_core]->event_loop->add_socket(client_fd, EPOLLIN | EPOLLET);
            core_loops_[target_core]->connections_count.fetch_add(1);
            
            std::cout << "📡 Connection " << client_fd 
                      << " assigned to core " << target_core << std::endl;
        }
    }
    
    size_t find_least_loaded_core() {
        size_t best_core = 0;
        uint64_t min_connections = core_loops_[0]->connections_count.load();
        
        for (size_t i = 1; i < num_cores_; ++i) {
            uint64_t connections = core_loops_[i]->connections_count.load();
            if (connections < min_connections) {
                min_connections = connections;
                best_core = i;
            }
        }
        
        return best_core;
    }
    
    void stop() {
        running_.store(false);
        
        for (auto& core_loop : core_loops_) {
            if (core_loop->thread && core_loop->thread->joinable()) {
                core_loop->thread->join();
            }
        }
        
        std::cout << "🛑 All core event loops stopped" << std::endl;
    }
    
    void print_core_stats() {
        std::cout << "\n📊 **CORE UTILIZATION STATS**:" << std::endl;
        for (size_t i = 0; i < num_cores_; ++i) {
            std::cout << "Core " << i << ": " 
                      << core_loops_[i]->connections_count.load() << " connections, "
                      << core_loops_[i]->requests_processed.load() << " requests" << std::endl;
        }
    }
};

} // namespace network
} // namespace meteor
