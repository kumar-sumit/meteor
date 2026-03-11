#include <iostream>
#include <memory>
#include <csignal>
#include <atomic>
#include <string>
#include <chrono>
#include <thread>

#include "../include/server/tcp_server.hpp"
#include "../include/cache/hybrid_cache.hpp"

using namespace meteor;

// Global server instance for signal handling
std::unique_ptr<server::TCPServer> g_server;
std::atomic<bool> g_shutdown_requested{false};

void print_banner() {
    std::cout << R"(
███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝
                                                      
   Redis-Compatible Ultra-High-Performance Cache     
                 Version 2.0.0 (C++)                 
            Memory + SSD Hybrid Architecture         
)" << std::endl;
}

void print_usage(const char* program_name) {
    std::cout << "Usage: " << program_name << " [OPTIONS]\n"
              << "Options:\n"
              << "  --host HOST              Server host (default: localhost)\n"
              << "  --port PORT              Server port (default: 6379)\n"
              << "  --max-connections N      Maximum concurrent connections (default: 10000)\n"
              << "  --max-memory BYTES       Maximum memory usage in bytes (default: 256MB)\n"
              << "  --max-entries N          Maximum memory entries (default: 100000)\n"
              << "  --worker-threads N       Number of worker threads (default: auto)\n"
              << "  --io-threads N           Number of I/O threads (default: auto)\n"
              << "  --enable-ssd             Enable SSD overflow storage\n"
              << "  --ssd-dir DIR            SSD storage directory (default: /tmp/meteor_cache)\n"
              << "  --ssd-page-size BYTES    SSD page size (default: 4096)\n"
              << "  --ssd-max-file-size BYTES Maximum SSD file size (default: 2GB)\n"
              << "  --enable-logging         Enable verbose logging\n"
              << "  --log-level LEVEL        Log level: DEBUG, INFO, WARN, ERROR (default: INFO)\n"
              << "  --help                   Show this help message\n"
              << "\n"
              << "Examples:\n"
              << "  " << program_name << " --port 6380 --enable-ssd --ssd-dir /tmp/meteor-cache\n"
              << "  " << program_name << " --host 0.0.0.0 --port 6379 --max-memory 512MB\n"
              << "  " << program_name << " --enable-logging --log-level DEBUG\n"
              << std::endl;
}

void signal_handler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        std::cout << "\nShutdown signal received, stopping server..." << std::endl;
        g_shutdown_requested.store(true);
        
        if (g_server) {
            g_server->stop();
        }
    }
}

size_t parse_memory_size(const std::string& str) {
    size_t value = 0;
    std::string unit;
    
    // Find the numeric part and unit
    size_t i = 0;
    while (i < str.length() && std::isdigit(str[i])) {
        value = value * 10 + (str[i] - '0');
        i++;
    }
    
    if (i < str.length()) {
        unit = str.substr(i);
        std::transform(unit.begin(), unit.end(), unit.begin(), ::toupper);
    }
    
    // Apply unit multiplier
    if (unit == "KB" || unit == "K") {
        value *= 1024;
    } else if (unit == "MB" || unit == "M") {
        value *= 1024 * 1024;
    } else if (unit == "GB" || unit == "G") {
        value *= 1024 * 1024 * 1024;
    } else if (!unit.empty()) {
        throw std::invalid_argument("Invalid memory unit: " + unit);
    }
    
    return value;
}

server::ServerConfig::LogLevel parse_log_level(const std::string& level) {
    std::string upper_level = level;
    std::transform(upper_level.begin(), upper_level.end(), upper_level.begin(), ::toupper);
    
    if (upper_level == "DEBUG") return server::ServerConfig::LogLevel::DEBUG;
    if (upper_level == "INFO") return server::ServerConfig::LogLevel::INFO;
    if (upper_level == "WARN") return server::ServerConfig::LogLevel::WARN;
    if (upper_level == "ERROR") return server::ServerConfig::LogLevel::ERROR;
    
    throw std::invalid_argument("Invalid log level: " + level);
}

int main(int argc, char* argv[]) {
    try {
        // Parse command line arguments
        server::ServerConfig server_config;
        cache::CacheConfig cache_config;
        
        for (int i = 1; i < argc; ++i) {
            std::string arg = argv[i];
            
            if (arg == "--help" || arg == "-h") {
                print_usage(argv[0]);
                return 0;
            } else if (arg == "--host" && i + 1 < argc) {
                server_config.host = argv[++i];
            } else if (arg.rfind("--host=", 0) == 0) {
                server_config.host = arg.substr(7);
            } else if (arg == "--port" && i + 1 < argc) {
                server_config.port = std::stoi(argv[++i]);
            } else if (arg.rfind("--port=", 0) == 0) {
                server_config.port = std::stoi(arg.substr(7));
            } else if (arg == "--max-connections" && i + 1 < argc) {
                server_config.max_connections = std::stoi(argv[++i]);
            } else if (arg.rfind("--max-connections=", 0) == 0) {
                server_config.max_connections = std::stoi(arg.substr(18));
            } else if (arg == "--max-memory" && i + 1 < argc) {
                cache_config.max_memory_bytes = parse_memory_size(argv[++i]);
            } else if (arg.rfind("--max-memory=", 0) == 0) {
                cache_config.max_memory_bytes = parse_memory_size(arg.substr(13));
            } else if (arg == "--max-entries" && i + 1 < argc) {
                cache_config.max_memory_entries = std::stoi(argv[++i]);
            } else if (arg.rfind("--max-entries=", 0) == 0) {
                cache_config.max_memory_entries = std::stoi(arg.substr(14));
            } else if (arg == "--worker-threads" && i + 1 < argc) {
                server_config.worker_threads = std::stoi(argv[++i]);
            } else if (arg.rfind("--worker-threads=", 0) == 0) {
                server_config.worker_threads = std::stoi(arg.substr(17));
            } else if (arg == "--io-threads" && i + 1 < argc) {
                server_config.io_threads = std::stoi(argv[++i]);
            } else if (arg.rfind("--io-threads=", 0) == 0) {
                server_config.io_threads = std::stoi(arg.substr(13));
            } else if (arg == "--enable-ssd") {
                cache_config.enable_ssd_overflow = true;
            } else if (arg == "--ssd-dir" && i + 1 < argc) {
                cache_config.ssd_directory = argv[++i];
            } else if (arg.rfind("--ssd-dir=", 0) == 0) {
                cache_config.ssd_directory = arg.substr(10);
            } else if (arg == "--ssd-page-size" && i + 1 < argc) {
                cache_config.ssd_page_size = std::stoi(argv[++i]);
            } else if (arg.rfind("--ssd-page-size=", 0) == 0) {
                cache_config.ssd_page_size = std::stoi(arg.substr(16));
            } else if (arg == "--ssd-max-file-size" && i + 1 < argc) {
                cache_config.max_ssd_file_size = parse_memory_size(argv[++i]);
            } else if (arg.rfind("--ssd-max-file-size=", 0) == 0) {
                cache_config.max_ssd_file_size = parse_memory_size(arg.substr(20));
            } else if (arg == "--enable-logging") {
                server_config.enable_logging = true;
            } else if (arg == "--log-level" && i + 1 < argc) {
                server_config.log_level = parse_log_level(argv[++i]);
            } else if (arg.rfind("--log-level=", 0) == 0) {
                server_config.log_level = parse_log_level(arg.substr(12));
            } else {
                std::cerr << "Unknown option: " << arg << std::endl;
                print_usage(argv[0]);
                return 1;
            }
        }
        
        // Print banner
        print_banner();
        
        // Create cache instance
        auto cache = std::make_shared<cache::HybridCache>(cache_config);
        
        // Create server instance
        g_server = std::make_unique<server::TCPServer>(server_config, cache);
        
        // Set up signal handlers
        std::signal(SIGINT, signal_handler);
        std::signal(SIGTERM, signal_handler);
        
        // Start cache
        cache->start();
        
        // Start server
        if (!g_server->start()) {
            std::cerr << "Failed to start server" << std::endl;
            return 1;
        }
        
        // Print startup information
        std::cout << "🚀 Meteor server started on " << server_config.host << ":" << server_config.port << std::endl;
        
        if (cache_config.enable_ssd_overflow) {
            std::cout << "💾 SSD overflow enabled: " << cache_config.ssd_directory << std::endl;
        } else {
            std::cout << "🧠 Pure in-memory mode" << std::endl;
        }
        
        std::cout << "📊 Max memory: " << (cache_config.max_memory_bytes / (1024 * 1024)) << " MB" << std::endl;
        std::cout << "🔧 Max connections: " << server_config.max_connections << std::endl;
        std::cout << "⚡ Worker threads: " << (server_config.worker_threads > 0 ? 
                                              std::to_string(server_config.worker_threads) : "auto") << std::endl;
        std::cout << "🏃 Ready to serve Redis clients!" << std::endl;
        
        if (server_config.enable_logging) {
            std::cout << "📝 Logging enabled (level: ";
            switch (server_config.log_level) {
                case server::ServerConfig::LogLevel::DEBUG: std::cout << "DEBUG"; break;
                case server::ServerConfig::LogLevel::INFO: std::cout << "INFO"; break;
                case server::ServerConfig::LogLevel::WARN: std::cout << "WARN"; break;
                case server::ServerConfig::LogLevel::ERROR: std::cout << "ERROR"; break;
            }
            std::cout << ")" << std::endl;
        }
        
        std::cout << "Press Ctrl+C to stop..." << std::endl;
        
        // Wait for shutdown signal
        while (!g_shutdown_requested.load() && g_server->is_running()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        
        // Print final statistics
        if (server_config.enable_logging) {
            auto stats = g_server->get_stats();
            auto cache_stats = cache->get_stats();
            
            std::cout << "\n📊 Final Statistics:" << std::endl;
            std::cout << "  Total connections: " << stats.total_connections.load() << std::endl;
            std::cout << "  Total requests: " << stats.total_requests.load() << std::endl;
            std::cout << "  Total responses: " << stats.total_responses.load() << std::endl;
            std::cout << "  Total errors: " << stats.total_errors.load() << std::endl;
            std::cout << "  Bytes read: " << stats.bytes_read.load() << std::endl;
            std::cout << "  Bytes written: " << stats.bytes_written.load() << std::endl;
            std::cout << "  Requests per second: " << stats.get_requests_per_second() << std::endl;
            std::cout << "  Average request time: " << stats.get_average_request_time_ms() << " ms" << std::endl;
            
            std::cout << "\n🧠 Cache Statistics:" << std::endl;
            std::cout << "  Cache hits: " << cache_stats.hits << std::endl;
            std::cout << "  Cache misses: " << cache_stats.misses << std::endl;
            std::cout << "  Hit rate: " << (cache_stats.hit_rate() * 100) << "%" << std::endl;
            std::cout << "  Memory entries: " << cache_stats.memory_entries << std::endl;
            std::cout << "  Memory usage: " << (cache_stats.memory_bytes / (1024 * 1024)) << " MB" << std::endl;
            std::cout << "  Evictions: " << cache_stats.evictions << std::endl;
            
            if (cache_config.enable_ssd_overflow) {
                std::cout << "  SSD entries: " << cache_stats.ssd_entries << std::endl;
                std::cout << "  SSD usage: " << (cache_stats.ssd_bytes / (1024 * 1024)) << " MB" << std::endl;
            }
        }
        
        // Stop cache
        cache->stop();
        
        std::cout << "Server stopped gracefully" << std::endl;
        std::cout << "Goodbye!" << std::endl;
        
        return 0;
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
} 