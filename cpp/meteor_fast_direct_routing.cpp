#include <iostream>
#include <string>
#include <vector>
#include <memory>
#include <atomic>
#include <thread>
#include <mutex>
#include <unordered_map>
#include <queue>
#include <chrono>
#include <algorithm>
#include <functional>

// **FAST DIRECT ROUTING**: Eliminate connection migration overhead
namespace fast_routing {
    
    // **SHARED SHARD ACCESS**: All cores can access all shards directly
    extern std::vector<std::unique_ptr<class ShardProcessor>> global_shards;
    extern std::atomic<size_t> shard_count;
    
    class ShardProcessor {
    private:
        size_t shard_id_;
        std::unordered_map<std::string, std::string> data_;
        std::mutex shard_mutex_;  // Fine-grained per-shard locking
        
    public:
        ShardProcessor(size_t shard_id) : shard_id_(shard_id) {}
        
        // **DIRECT SHARD OPERATIONS**: No connection migration needed
        std::string process_command(const std::string& command, const std::string& key, const std::string& value) {
            std::lock_guard<std::mutex> lock(shard_mutex_);
            
            if (command == "SET" || command == "set") {
                data_[key] = value;
                return "+OK\r\n";
            } else if (command == "GET" || command == "get") {
                auto it = data_.find(key);
                if (it != data_.end()) {
                    return "$" + std::to_string(it->second.length()) + "\r\n" + it->second + "\r\n";
                } else {
                    return "$-1\r\n";
                }
            } else if (command == "DEL" || command == "del") {
                auto it = data_.find(key);
                if (it != data_.end()) {
                    data_.erase(it);
                    return ":1\r\n";
                } else {
                    return ":0\r\n";
                }
            }
            return "-ERR unknown command\r\n";
        }
    };
    
    // **FAST ROUTING**: Direct shard access without connection migration
    inline std::string route_command(const std::string& command, const std::string& key, const std::string& value) {
        if (key.empty()) {
            // Non-key commands
            if (command == "PING" || command == "ping") {
                return "+PONG\r\n";
            }
            return "-ERR missing key\r\n";
        }
        
        // **DIRECT SHARD ROUTING**: Calculate target shard and process directly
        size_t target_shard = std::hash<std::string>{}(key) % shard_count.load();
        return global_shards[target_shard]->process_command(command, key, value);
    }
}

// Global shard storage
std::vector<std::unique_ptr<fast_routing::ShardProcessor>> fast_routing::global_shards;
std::atomic<size_t> fast_routing::shard_count{0};

int main(int argc, char* argv[]) {
    // Initialize global shards
    size_t num_shards = 4;  // cores = shards
    fast_routing::shard_count = num_shards;
    
    for (size_t i = 0; i < num_shards; ++i) {
        fast_routing::global_shards.push_back(std::make_unique<fast_routing::ShardProcessor>(i));
    }
    
    std::cout << "🚀 Fast Direct Routing Server: " << num_shards << " shards initialized" << std::endl;
    std::cout << "✅ Zero connection migration overhead" << std::endl;
    std::cout << "✅ Direct shard access pattern" << std::endl;
    
    // Simple test
    auto result1 = fast_routing::route_command("SET", "test_key", "test_value");
    auto result2 = fast_routing::route_command("GET", "test_key", "");
    
    std::cout << "SET result: " << result1.substr(0, result1.find('\r'));
    std::cout << "GET result: " << result2.substr(0, result2.find('\r'));
    
    return 0;
}













