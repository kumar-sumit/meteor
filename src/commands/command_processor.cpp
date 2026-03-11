#include "command_processor.hpp"
#include "../core/shard_manager.hpp"
#include <iostream>

namespace garuda {

CommandProcessor::CommandProcessor(ShardManager* shard_manager) : shard_manager_(shard_manager) {
    std::cout << "⚡ Creating Command Processor (Redis protocol)..." << std::endl;
}

CommandProcessor::~CommandProcessor() = default;

std::string CommandProcessor::process_command(const std::string& command) {
    // Placeholder implementation
    // In a real implementation, this would:
    // 1. Parse Redis protocol (RESP)
    // 2. Extract command and arguments
    // 3. Route to appropriate shard via ShardManager
    // 4. Format response in RESP format
    
    if (command.find("PING") != std::string::npos) {
        return "+PONG\r\n";
    }
    
    return "+OK\r\n";
}

} // namespace garuda