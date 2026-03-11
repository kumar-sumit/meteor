#include <iostream>
#include <csignal>
#include <string>
#include <thread>
#include <chrono>
#include <getopt.h>

#include "meteor/server/tcp_server.hpp"
#include "meteor/cache/hybrid_cache.hpp"
#include "meteor/protocol/resp_parser.hpp"

using namespace meteor;

// Global server instance for signal handling
static std::unique_ptr<server::TCPServer> g_server;
static std::unique_ptr<cache::HybridCache> g_cache;
static std::atomic<bool> g_shutdown_requested{false};

// Signal handler for graceful shutdown
void signal_handler(int signal) {
    std::cout << "\nShutdown signal received, stopping server..." << std::endl;
    g_shutdown_requested = true;
    
    if (g_server) {
        g_server->stop();
    }
    if (g_cache) {
        g_cache->stop();
    }
}

// Command handler implementation
protocol::RESPValue handle_command(const protocol::RESPValue& command) {
    if (command.type != protocol::RESPType::ARRAY || command.array_value.empty()) {
        return protocol::create_error("ERR Protocol error");
    }

    // Extract command name
    const auto& cmd_value = command.array_value[0];
    if (cmd_value.type != protocol::RESPType::BULK_STRING) {
        return protocol::create_error("ERR Protocol error");
    }

    std::string cmd_name = cmd_value.string_value;
    std::transform(cmd_name.begin(), cmd_name.end(), cmd_name.begin(), ::toupper);

    // Handle PING command
    if (cmd_name == "PING") {
        if (command.array_value.size() == 1) {
            return protocol::create_simple_string("PONG");
        } else if (command.array_value.size() == 2) {
            return protocol::create_bulk_string(command.array_value[1].string_value);
        }
        return protocol::create_error("ERR wrong number of arguments for 'ping' command");
    }

    // Handle GET command
    if (cmd_name == "GET") {
        if (command.array_value.size() != 2) {
            return protocol::create_error("ERR wrong number of arguments for 'get' command");
        }

        const std::string& key = command.array_value[1].string_value;
        auto result = g_cache->get(key);
        
        if (result.has_value()) {
            return protocol::create_bulk_string(result.value());
        } else {
            return protocol::create_nil();
        }
    }

    // Handle SET command
    if (cmd_name == "SET") {
        if (command.array_value.size() < 3) {
            return protocol::create_error("ERR wrong number of arguments for 'set' command");
        }

        const std::string& key = command.array_value[1].string_value;
        const std::string& value = command.array_value[2].string_value;
        
        std::chrono::seconds ttl{0}; // Use default TTL
        
        // Parse optional TTL arguments
        for (size_t i = 3; i < command.array_value.size(); i += 2) {
            if (i + 1 >= command.array_value.size()) {
                return protocol::create_error("ERR syntax error");
            }
            
            std::string option = command.array_value[i].string_value;
            std::transform(option.begin(), option.end(), option.begin(), ::toupper);
            
            if (option == "EX") {
                try {
                    ttl = std::chrono::seconds(std::stoi(command.array_value[i + 1].string_value));
                } catch (const std::exception&) {
                    return protocol::create_error("ERR invalid expire time");
                }
            }
        }

        if (g_cache->put(key, value, ttl)) {
            return protocol::create_simple_string("OK");
        } else {
            return protocol::create_error("ERR failed to set key");
        }
    }

    // Handle DEL command
    if (cmd_name == "DEL") {
        if (command.array_value.size() < 2) {
            return protocol::create_error("ERR wrong number of arguments for 'del' command");
        }

        int64_t deleted_count = 0;
        for (size_t i = 1; i < command.array_value.size(); ++i) {
            const std::string& key = command.array_value[i].string_value;
            if (g_cache->remove(key)) {
                deleted_count++;
            }
        }

        return protocol::create_integer(deleted_count);
    }

    // Handle EXISTS command
    if (cmd_name == "EXISTS") {
        if (command.array_value.size() < 2) {
            return protocol::create_error("ERR wrong number of arguments for 'exists' command");
        }

        int64_t exists_count = 0;
        for (size_t i = 1; i < command.array_value.size(); ++i) {
            const std::string& key = command.array_value[i].string_value;
            if (g_cache->contains(key)) {
                exists_count++;
            }
        }

        return protocol::create_integer(exists_count);
    }

    // Handle FLUSHALL command
    if (cmd_name == "FLUSHALL") {
        g_cache->clear();
        return protocol::create_simple_string("OK");
    }

    // Handle INFO command
    if (cmd_name == "INFO") {
        auto stats = g_cache->get_stats();
        auto server_stats = g_server->get_stats();
        
        std::string info = "# Server\r\n";
        info += "redis_version:7.0.0\r\n";
        info += "meteor_version:2.0.0\r\n";
        info += "os:Darwin\r\n";
        info += "arch_bits:64\r\n";
        info += "multiplexing_api:kqueue\r\n";
        info += "process_id:" + std::to_string(getpid()) + "\r\n";
        info += "run_id:random\r\n";
        info += "tcp_port:" + std::to_string(6380) + "\r\n";
        info += "\r\n";
        
        info += "# Clients\r\n";
        info += "connected_clients:" + std::to_string(server_stats.active_connections) + "\r\n";
        info += "client_recent_max_input_buffer:0\r\n";
        info += "client_recent_max_output_buffer:0\r\n";
        info += "blocked_clients:0\r\n";
        info += "tracking_clients:0\r\n";
        info += "clients_in_timeout_table:0\r\n";
        info += "\r\n";
        
        info += "# Memory\r\n";
        info += "used_memory:" + std::to_string(stats.memory_usage) + "\r\n";
        info += "used_memory_human:" + std::to_string(stats.memory_usage / 1024 / 1024) + "M\r\n";
        info += "used_memory_rss:" + std::to_string(stats.memory_usage) + "\r\n";
        info += "used_memory_peak:" + std::to_string(stats.memory_usage) + "\r\n";
        info += "total_system_memory:0\r\n";
        info += "used_memory_lua:0\r\n";
        info += "maxmemory:0\r\n";
        info += "maxmemory_human:0B\r\n";
        info += "maxmemory_policy:noeviction\r\n";
        info += "mem_fragmentation_ratio:1.0\r\n";
        info += "mem_allocator:jemalloc-5.2.1\r\n";
        info += "\r\n";
        
        info += "# Stats\r\n";
        info += "total_connections_received:" + std::to_string(server_stats.total_connections) + "\r\n";
        info += "total_commands_processed:" + std::to_string(server_stats.total_requests) + "\r\n";
        info += "instantaneous_ops_per_sec:0\r\n";
        info += "total_net_input_bytes:0\r\n";
        info += "total_net_output_bytes:0\r\n";
        info += "instantaneous_input_kbps:0\r\n";
        info += "instantaneous_output_kbps:0\r\n";
        info += "rejected_connections:0\r\n";
        info += "sync_full:0\r\n";
        info += "sync_partial_ok:0\r\n";
        info += "sync_partial_err:0\r\n";
        info += "expired_keys:0\r\n";
        info += "expired_stale_perc:0.00\r\n";
        info += "expired_time_cap_reached_count:0\r\n";
        info += "evicted_keys:" + std::to_string(stats.evictions) + "\r\n";
        info += "keyspace_hits:" + std::to_string(stats.memory_hits) + "\r\n";
        info += "keyspace_misses:" + std::to_string(stats.memory_misses) + "\r\n";
        info += "pubsub_channels:0\r\n";
        info += "pubsub_patterns:0\r\n";
        info += "latest_fork_usec:0\r\n";
        info += "migrate_cached_sockets:0\r\n";
        info += "slave_expires_tracked_keys:0\r\n";
        info += "active_defrag_hits:0\r\n";
        info += "active_defrag_misses:0\r\n";
        info += "active_defrag_key_hits:0\r\n";
        info += "active_defrag_key_misses:0\r\n";
        info += "\r\n";
        
        info += "# Keyspace\r\n";
        info += "db0:keys=" + std::to_string(stats.memory_entries) + ",expires=0,avg_ttl=0\r\n";
        
        return protocol::create_bulk_string(info);
    }

    // Handle COMMAND command
    if (cmd_name == "COMMAND") {
        // Return empty array for now
        return protocol::create_array({});
    }

    // Handle QUIT command
    if (cmd_name == "QUIT") {
        return protocol::create_simple_string("OK");
    }

    // Unknown command
    return protocol::create_error("ERR unknown command '" + cmd_name + "'");
}

void print_usage(const char* program_name) {
    std::cout << "Usage: " << program_name << " [OPTIONS]\n";
    std::cout << "Options:\n";
    std::cout << "  --host HOST              Server host (default: localhost)\n";
    std::cout << "  --port PORT              Server port (default: 6379)\n";
    std::cout << "  --tiered-prefix DIR      Cache directory for tiered storage (hybrid mode)\n";
    std::cout << "  --max-connections N      Maximum concurrent connections (default: 1000)\n";
    std::cout << "  --buffer-size N          Buffer size in bytes (default: 65536)\n";
    std::cout << "  --enable-logging         Enable verbose logging\n";
    std::cout << "  --help                   Show this help message\n";
    std::cout << "Examples:\n";
    std::cout << "  " << program_name << " --port 6380 --tiered-prefix /tmp/meteor-cache\n";
    std::cout << "  " << program_name << " --host 0.0.0.0 --port 6379 --enable-logging\n";
}

void print_banner() {
    std::cout << R"(
███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝
                                                      
          Redis-Compatible High-Performance Cache     
                      Version 2.0.0                  
)" << std::endl;
}

int main(int argc, char* argv[]) {
    // Default configuration
    server::Config server_config;
    cache::Config cache_config;
    
    // Parse command line arguments
    static struct option long_options[] = {
        {"host", required_argument, 0, 'h'},
        {"port", required_argument, 0, 'p'},
        {"tiered-prefix", required_argument, 0, 't'},
        {"max-connections", required_argument, 0, 'm'},
        {"buffer-size", required_argument, 0, 'b'},
        {"enable-logging", no_argument, 0, 'l'},
        {"help", no_argument, 0, '?'},
        {0, 0, 0, 0}
    };
    
    int option_index = 0;
    int c;
    
    while ((c = getopt_long(argc, argv, "h:p:t:m:b:l?", long_options, &option_index)) != -1) {
        switch (c) {
            case 'h':
                server_config.host = optarg;
                break;
            case 'p':
                server_config.port = std::stoi(optarg);
                break;
            case 't':
                cache_config.tiered_prefix = optarg;
                break;
            case 'm':
                server_config.max_connections = std::stoul(optarg);
                break;
            case 'b':
                server_config.buffer_size = std::stoul(optarg);
                break;
            case 'l':
                server_config.enable_logging = true;
                break;
            case '?':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    // Print banner
    print_banner();
    
    // Print configuration
    std::cout << "🚀 Meteor server starting on " << server_config.host << ":" << server_config.port << std::endl;
    
    if (!cache_config.tiered_prefix.empty()) {
        std::cout << "✅ Hybrid cache enabled with SSD storage: " << cache_config.tiered_prefix << std::endl;
        std::cout << "✅ Async I/O enabled (io_uring/kqueue)" << std::endl;
    } else {
        std::cout << "📝 Pure in-memory cache mode" << std::endl;
    }
    
    std::cout << "✅ Zero-copy RESP parsing enabled" << std::endl;
    std::cout << "✅ Memory pools enabled" << std::endl;
    std::cout << "✅ TCP optimizations enabled" << std::endl;
    std::cout << "✅ Connection pooling enabled" << std::endl;
    std::cout << "📊 Buffer size: " << server_config.buffer_size << " bytes" << std::endl;
    std::cout << "🔧 Max connections: " << server_config.max_connections << std::endl;
    std::cout << "🏃 Ready to serve Redis clients!" << std::endl;
    std::cout << "Press Ctrl+C to stop..." << std::endl;
    
    // Set up signal handlers
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);
    
    try {
        // Initialize cache
        g_cache = std::make_unique<cache::HybridCache>(cache_config);
        g_cache->start();
        
        // Initialize server
        g_server = std::make_unique<server::TCPServer>(server_config);
        g_server->set_command_handler(handle_command);
        
        // Start server
        if (!g_server->start()) {
            std::cerr << "Failed to start server" << std::endl;
            return 1;
        }
        
        // Main loop
        while (!g_shutdown_requested) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    
    std::cout << "Server stopped gracefully" << std::endl;
    std::cout << "Goodbye!" << std::endl;
    
    return 0;
} 