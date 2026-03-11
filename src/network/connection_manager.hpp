#pragma once

#include <atomic>
#include <memory>
#include <unordered_map>
#include <string>

namespace garuda {

// Connection Manager for Helio Server
class ConnectionManager {
public:
    ConnectionManager();
    ~ConnectionManager();
    
    // Connection management
    void add_connection(int fd);
    void remove_connection(int fd);
    
    // Statistics
    size_t get_active_connections() const { return active_connections_.load(); }
    
private:
    std::atomic<size_t> active_connections_{0};
    std::unordered_map<int, std::string> connections_;
};

} // namespace garuda