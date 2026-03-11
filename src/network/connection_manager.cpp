#include "connection_manager.hpp"
#include <iostream>

namespace garuda {

ConnectionManager::ConnectionManager() {
    std::cout << "🔗 Creating Connection Manager..." << std::endl;
}

ConnectionManager::~ConnectionManager() = default;

void ConnectionManager::add_connection(int fd) {
    active_connections_.fetch_add(1);
    connections_[fd] = "active";
}

void ConnectionManager::remove_connection(int fd) {
    auto it = connections_.find(fd);
    if (it != connections_.end()) {
        connections_.erase(it);
        active_connections_.fetch_sub(1);
    }
}

} // namespace garuda