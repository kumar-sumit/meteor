#include "redis_commands.hpp"
#include <algorithm>
#include <sstream>
#include <chrono>
#include <iostream>

namespace garuda::commands {

RedisCommandHandler::RedisCommandHandler() 
    : dashtable_(std::make_unique<core::Dashtable>(1024, 8)) {
    
    // Register Redis commands
    commands_["PING"] = [this](const auto& args) { return HandlePing(args); };
    commands_["SET"] = [this](const auto& args) { return HandleSet(args); };
    commands_["GET"] = [this](const auto& args) { return HandleGet(args); };
    commands_["DEL"] = [this](const auto& args) { return HandleDel(args); };
    commands_["EXISTS"] = [this](const auto& args) { return HandleExists(args); };
    commands_["KEYS"] = [this](const auto& args) { return HandleKeys(args); };
    commands_["FLUSHALL"] = [this](const auto& args) { return HandleFlushAll(args); };
    commands_["DBSIZE"] = [this](const auto& args) { return HandleDbSize(args); };
    commands_["INFO"] = [this](const auto& args) { return HandleInfo(args); };
    commands_["COMMAND"] = [this](const auto& args) { return HandleCommand(args); };
    commands_["SELECT"] = [this](const auto& args) { return HandleSelect(args); };
    commands_["QUIT"] = [this](const auto& args) { return HandleQuit(args); };
}

protocol::RespValue RedisCommandHandler::ProcessCommand(const protocol::RespValue& command) {
    stats_.total_commands.fetch_add(1);
    
    try {
        // Extract command arguments
        auto args = ExtractArgs(command);
        if (args.empty()) {
            stats_.errors.fetch_add(1);
            return CreateError("ERR empty command");
        }
        
        // Convert command to uppercase
        std::string cmd = ToUpper(args[0]);
        
        // Find and execute command
        auto it = commands_.find(cmd);
        if (it != commands_.end()) {
            return it->second(args);
        } else {
            stats_.unknown_commands.fetch_add(1);
            return CreateError("ERR unknown command '" + args[0] + "'");
        }
        
    } catch (const std::exception& e) {
        stats_.errors.fetch_add(1);
        return CreateError("ERR " + std::string(e.what()));
    }
}

std::vector<std::string> RedisCommandHandler::ExtractArgs(const protocol::RespValue& command) {
    std::vector<std::string> args;
    
    if (command.type == protocol::RespType::ARRAY) {
        args.reserve(command.array_val.size());
        for (const auto& arg : command.array_val) {
            if (arg.type == protocol::RespType::BULK_STRING) {
                args.push_back(arg.str_val);
            } else if (arg.type == protocol::RespType::SIMPLE_STRING) {
                args.push_back(arg.str_val);
            }
        }
    } else if (command.type == protocol::RespType::BULK_STRING || 
               command.type == protocol::RespType::SIMPLE_STRING) {
        // Single command
        args.push_back(command.str_val);
    }
    
    return args;
}

std::string RedisCommandHandler::ToUpper(const std::string& str) {
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), ::toupper);
    return result;
}

protocol::RespValue RedisCommandHandler::CreateError(const std::string& message) {
    return protocol::RespValue::CreateError(message);
}

protocol::RespValue RedisCommandHandler::HandlePing(const std::vector<std::string>& args) {
    stats_.ping_commands.fetch_add(1);
    
    if (args.size() == 1) {
        return protocol::RespValue::CreateSimpleString("PONG");
    } else if (args.size() == 2) {
        return protocol::RespValue(args[1]); // Echo the message
    } else {
        return CreateError("ERR wrong number of arguments for 'ping' command");
    }
}

protocol::RespValue RedisCommandHandler::HandleSet(const std::vector<std::string>& args) {
    stats_.set_commands.fetch_add(1);
    
    if (args.size() < 3) {
        return CreateError("ERR wrong number of arguments for 'set' command");
    }
    
    const std::string& key = args[1];
    const std::string& value = args[2];
    
    // For now, ignore additional SET options like EX, PX, NX, XX
    // TODO: Implement full SET command options
    
    {
        std::unique_lock<std::shared_mutex> lock(data_mutex_);
        dashtable_->Set(key, value);
    }
    
    return protocol::RespValue::CreateSimpleString("OK");
}

protocol::RespValue RedisCommandHandler::HandleGet(const std::vector<std::string>& args) {
    stats_.get_commands.fetch_add(1);
    
    if (args.size() != 2) {
        return CreateError("ERR wrong number of arguments for 'get' command");
    }
    
    const std::string& key = args[1];
    
    {
        std::shared_lock<std::shared_mutex> lock(data_mutex_);
        auto value = dashtable_->Get(key);
        if (value) {
            return protocol::RespValue(*value);
        } else {
            return protocol::RespValue::CreateNull();
        }
    }
}

protocol::RespValue RedisCommandHandler::HandleDel(const std::vector<std::string>& args) {
    stats_.del_commands.fetch_add(1);
    
    if (args.size() < 2) {
        return CreateError("ERR wrong number of arguments for 'del' command");
    }
    
    int64_t deleted_count = 0;
    
    {
        std::unique_lock<std::shared_mutex> lock(data_mutex_);
        for (size_t i = 1; i < args.size(); ++i) {
            if (dashtable_->Delete(args[i])) {
                deleted_count++;
            }
        }
    }
    
    return protocol::RespValue(deleted_count);
}

protocol::RespValue RedisCommandHandler::HandleExists(const std::vector<std::string>& args) {
    stats_.exists_commands.fetch_add(1);
    
    if (args.size() < 2) {
        return CreateError("ERR wrong number of arguments for 'exists' command");
    }
    
    int64_t exists_count = 0;
    
    {
        std::shared_lock<std::shared_mutex> lock(data_mutex_);
        for (size_t i = 1; i < args.size(); ++i) {
            if (dashtable_->Exists(args[i])) {
                exists_count++;
            }
        }
    }
    
    return protocol::RespValue(exists_count);
}

protocol::RespValue RedisCommandHandler::HandleKeys(const std::vector<std::string>& args) {
    if (args.size() != 2) {
        return CreateError("ERR wrong number of arguments for 'keys' command");
    }
    
    const std::string& pattern = args[1];
    
    // For simplicity, only support "*" pattern for now
    if (pattern != "*") {
        return CreateError("ERR pattern matching not implemented yet");
    }
    
    std::vector<protocol::RespValue> keys;
    
    {
        std::shared_lock<std::shared_mutex> lock(data_mutex_);
        auto all_keys = dashtable_->GetAllKeys();
        keys.reserve(all_keys.size());
        
        for (const auto& key : all_keys) {
            keys.emplace_back(key);
        }
    }
    
    return protocol::RespValue::CreateArray(std::move(keys));
}

protocol::RespValue RedisCommandHandler::HandleFlushAll(const std::vector<std::string>& args) {
    // Ignore ASYNC option for now
    
    {
        std::unique_lock<std::shared_mutex> lock(data_mutex_);
        dashtable_->Clear();
    }
    
    return protocol::RespValue::CreateSimpleString("OK");
}

protocol::RespValue RedisCommandHandler::HandleDbSize(const std::vector<std::string>& args) {
    if (args.size() != 1) {
        return CreateError("ERR wrong number of arguments for 'dbsize' command");
    }
    
    {
        std::shared_lock<std::shared_mutex> lock(data_mutex_);
        int64_t size = static_cast<int64_t>(dashtable_->Size());
        return protocol::RespValue(size);
    }
}

protocol::RespValue RedisCommandHandler::HandleInfo(const std::vector<std::string>& args) {
    std::ostringstream info;
    
    // Server section
    info << "# Server\r\n";
    info << "redis_version:7.0.0\r\n";
    info << "redis_git_sha1:00000000\r\n";
    info << "redis_git_dirty:0\r\n";
    info << "redis_build_id:00000000\r\n";
    info << "redis_mode:standalone\r\n";
    info << "os:Linux\r\n";
    info << "arch_bits:64\r\n";
    info << "multiplexing_api:epoll\r\n";
    info << "gcc_version:11.4.0\r\n";
    info << "process_id:1\r\n";
    info << "tcp_port:6379\r\n";
    
    // Stats section
    info << "\r\n# Stats\r\n";
    info << "total_connections_received:" << stats_.total_commands.load() << "\r\n";
    info << "total_commands_processed:" << stats_.total_commands.load() << "\r\n";
    info << "instantaneous_ops_per_sec:0\r\n";
    info << "total_net_input_bytes:0\r\n";
    info << "total_net_output_bytes:0\r\n";
    info << "rejected_connections:0\r\n";
    info << "sync_full:0\r\n";
    info << "sync_partial_ok:0\r\n";
    info << "sync_partial_err:0\r\n";
    info << "expired_keys:0\r\n";
    info << "evicted_keys:0\r\n";
    info << "keyspace_hits:" << stats_.get_commands.load() << "\r\n";
    info << "keyspace_misses:0\r\n";
    
    // Memory section  
    info << "\r\n# Memory\r\n";
    info << "used_memory:1000000\r\n";
    info << "used_memory_human:976.56K\r\n";
    info << "used_memory_rss:2000000\r\n";
    info << "used_memory_rss_human:1.91M\r\n";
    info << "used_memory_peak:2000000\r\n";
    info << "used_memory_peak_human:1.91M\r\n";
    
    // Keyspace section
    {
        std::shared_lock<std::shared_mutex> lock(data_mutex_);
        size_t db_size = dashtable_->Size();
        if (db_size > 0) {
            info << "\r\n# Keyspace\r\n";
            info << "db" << current_db_ << ":keys=" << db_size << ",expires=0,avg_ttl=0\r\n";
        }
    }
    
    return protocol::RespValue(info.str());
}

protocol::RespValue RedisCommandHandler::HandleCommand(const std::vector<std::string>& args) {
    // Return empty array for COMMAND - Redis client compatibility
    return protocol::RespValue::CreateArray({});
}

protocol::RespValue RedisCommandHandler::HandleSelect(const std::vector<std::string>& args) {
    if (args.size() != 2) {
        return CreateError("ERR wrong number of arguments for 'select' command");
    }
    
    try {
        int db_index = std::stoi(args[1]);
        if (db_index < 0 || db_index >= MAX_DATABASES) {
            return CreateError("ERR DB index is out of range");
        }
        
        current_db_ = db_index;
        return protocol::RespValue::CreateSimpleString("OK");
    } catch (const std::exception&) {
        return CreateError("ERR value is not an integer or out of range");
    }
}

protocol::RespValue RedisCommandHandler::HandleQuit(const std::vector<std::string>& args) {
    return protocol::RespValue::CreateSimpleString("OK");
}

} // namespace garuda::commands