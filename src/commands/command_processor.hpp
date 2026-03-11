#pragma once

#include <memory>
#include <string>

namespace garuda {

// Forward declarations
class ShardManager;

// Command Processor for Redis protocol compatibility
class CommandProcessor {
public:
    explicit CommandProcessor(ShardManager* shard_manager);
    ~CommandProcessor();
    
    // Process Redis command
    std::string process_command(const std::string& command);
    
private:
    ShardManager* shard_manager_;
};

} // namespace garuda