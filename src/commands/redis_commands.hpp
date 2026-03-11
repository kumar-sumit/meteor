#pragma once

#include "../protocol/resp_parser.hpp"
#include "../core/dashtable.hpp"
#include <unordered_map>
#include <string>
#include <functional>
#include <memory>
#include <shared_mutex>

namespace garuda::commands {

class RedisCommandHandler {
public:
    explicit RedisCommandHandler();
    ~RedisCommandHandler() = default;
    
    // Process a Redis command and return response
    protocol::RespValue ProcessCommand(const protocol::RespValue& command);
    
    // Command statistics
    struct Stats {
        std::atomic<uint64_t> total_commands{0};
        std::atomic<uint64_t> get_commands{0};
        std::atomic<uint64_t> set_commands{0};
        std::atomic<uint64_t> del_commands{0};
        std::atomic<uint64_t> exists_commands{0};
        std::atomic<uint64_t> ping_commands{0};
        std::atomic<uint64_t> unknown_commands{0};
        std::atomic<uint64_t> errors{0};
    };
    
    const Stats& GetStats() const { return stats_; }
    
private:
    using CommandFunction = std::function<protocol::RespValue(const std::vector<std::string>&)>;
    
    // Core Redis commands
    protocol::RespValue HandlePing(const std::vector<std::string>& args);
    protocol::RespValue HandleSet(const std::vector<std::string>& args);
    protocol::RespValue HandleGet(const std::vector<std::string>& args);
    protocol::RespValue HandleDel(const std::vector<std::string>& args);
    protocol::RespValue HandleExists(const std::vector<std::string>& args);
    protocol::RespValue HandleKeys(const std::vector<std::string>& args);
    protocol::RespValue HandleFlushAll(const std::vector<std::string>& args);
    protocol::RespValue HandleDbSize(const std::vector<std::string>& args);
    protocol::RespValue HandleInfo(const std::vector<std::string>& args);
    protocol::RespValue HandleCommand(const std::vector<std::string>& args);
    protocol::RespValue HandleSelect(const std::vector<std::string>& args);
    protocol::RespValue HandleQuit(const std::vector<std::string>& args);
    
    // Utility functions
    std::vector<std::string> ExtractArgs(const protocol::RespValue& command);
    std::string ToUpper(const std::string& str);
    protocol::RespValue CreateError(const std::string& message);
    
    // Data storage - using Dragonfly-style dashtable
    std::unique_ptr<core::Dashtable> dashtable_;
    
    // Command registry
    std::unordered_map<std::string, CommandFunction> commands_;
    
    // Thread safety
    mutable std::shared_mutex data_mutex_;
    
    // Statistics
    mutable Stats stats_;
    
    // Database selection (Redis compatibility)
    int current_db_ = 0;
    static constexpr int MAX_DATABASES = 16;
};

} // namespace garuda::commands