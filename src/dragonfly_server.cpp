#include "network/dragonfly_connection.hpp"
#include "commands/redis_commands.hpp"
#include "core/dashtable.hpp"
#include <iostream>
#include <signal.h>
#include <atomic>
#include <thread>
#include <chrono>

namespace {
std::atomic<bool> g_shutdown{false};

void SignalHandler(int signal) {
    std::cout << "\nReceived signal " << signal << ", shutting down..." << std::endl;
    g_shutdown.store(true);
}
} // anonymous namespace

int main(int argc, char* argv[]) {
    // Parse command line arguments
    int port = 6379;
    if (argc > 1) {
        try {
            port = std::stoi(argv[1]);
            if (port < 1 || port > 65535) {
                std::cerr << "Error: Invalid port number. Must be between 1 and 65535." << std::endl;
                return 1;
            }
        } catch (const std::exception&) {
            std::cerr << "Error: Invalid port number: " << argv[1] << std::endl;
            return 1;
        }
    }
    
    // Setup signal handlers
    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);
    
    std::cout << "🚀 GarudaDB - Authentic Dragonfly Implementation v2.0.0" << std::endl;
    std::cout << "⚡ Starting Dragonfly-compatible Redis server..." << std::endl;
    
    // Create command handler
    auto command_handler = std::make_shared<garuda::commands::RedisCommandHandler>();
    
    // Create and start server
    garuda::network::DragonflyServer server(port);
    
    // Set command handler
    server.SetCommandHandler([command_handler](const garuda::protocol::RespValue& command) {
        return command_handler->ProcessCommand(command);
    });
    
    if (!server.Start()) {
        std::cerr << "Failed to start server on port " << port << std::endl;
        return 1;
    }
    
    std::cout << "✅ Server listening on port " << port << std::endl;
    std::cout << "📊 Ready to accept Redis-compatible connections" << std::endl;
    std::cout << "🔧 Supports commands: PING, GET, SET, DEL, EXISTS, KEYS, FLUSHALL, DBSIZE, INFO, etc." << std::endl;
    std::cout << "💡 Test with: redis-cli -p " << port << " ping" << std::endl;
    std::cout << "🏁 Press Ctrl+C to shutdown" << std::endl;
    
    // Statistics reporting thread
    std::thread stats_thread([&server, &command_handler]() {
        auto last_commands = 0UL;
        auto last_time = std::chrono::steady_clock::now();
        
        while (!g_shutdown.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(10));
            
            if (g_shutdown.load()) break;
            
            auto now = std::chrono::steady_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::seconds>(now - last_time);
            
            const auto& server_stats = server.GetStats();
            const auto& cmd_stats = command_handler->GetStats();
            
            auto current_commands = cmd_stats.total_commands.load();
            auto commands_delta = current_commands - last_commands;
            auto qps = duration.count() > 0 ? commands_delta / duration.count() : 0;
            
            std::cout << "📈 Stats: " 
                      << "Connections=" << server_stats.active_connections.load() 
                      << ", Commands=" << current_commands
                      << ", QPS=" << qps
                      << ", GET=" << cmd_stats.get_commands.load()
                      << ", SET=" << cmd_stats.set_commands.load()
                      << ", Errors=" << cmd_stats.errors.load()
                      << std::endl;
            
            last_commands = current_commands;
            last_time = now;
        }
    });
    
    // Main loop
    while (!g_shutdown.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    std::cout << "🛑 Shutting down server..." << std::endl;
    server.Stop();
    
    if (stats_thread.joinable()) {
        stats_thread.join();
    }
    
    // Final statistics
    const auto& server_stats = server.GetStats();
    const auto& cmd_stats = command_handler->GetStats();
    
    std::cout << "\n📊 Final Statistics:" << std::endl;
    std::cout << "  Total Connections: " << server_stats.total_connections.load() << std::endl;
    std::cout << "  Total Commands: " << cmd_stats.total_commands.load() << std::endl;
    std::cout << "  GET Commands: " << cmd_stats.get_commands.load() << std::endl;
    std::cout << "  SET Commands: " << cmd_stats.set_commands.load() << std::endl;
    std::cout << "  DEL Commands: " << cmd_stats.del_commands.load() << std::endl;
    std::cout << "  PING Commands: " << cmd_stats.ping_commands.load() << std::endl;
    std::cout << "  Errors: " << cmd_stats.errors.load() << std::endl;
    
    std::cout << "\n✅ GarudaDB shutdown complete. Thank you for using authentic Dragonfly architecture!" << std::endl;
    
    return 0;
}