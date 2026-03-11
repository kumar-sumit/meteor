#include <iostream>
#include <chrono>
#include <thread>
#include <vector>
#include <random>
#include <atomic>
#include <memory>
#include <future>
#include <iomanip>
#include <fstream>
#include <sstream>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>

// Benchmark configuration
struct BenchmarkConfig {
    std::string host = "localhost";
    uint16_t port = 6379;
    
    // Load parameters
    size_t num_clients = 50;
    size_t num_requests = 100000;
    size_t pipeline_size = 10;
    size_t key_size = 16;
    size_t value_size = 64;
    
    // Test types
    bool test_get = true;
    bool test_set = true;
    bool test_ping = true;
    bool test_mixed = true;
    
    // Advanced tests
    bool test_pipeline = true;
    bool test_batch = true;
    bool test_concurrent = true;
    
    // Duration test
    std::chrono::seconds duration = std::chrono::seconds(30);
    
    // Output
    std::string output_file = "benchmark_results.csv";
    bool verbose = false;
};

// Benchmark results
struct BenchmarkResult {
    std::string test_name;
    size_t total_requests = 0;
    size_t successful_requests = 0;
    size_t failed_requests = 0;
    std::chrono::microseconds total_time{0};
    std::chrono::microseconds min_latency{std::chrono::microseconds::max()};
    std::chrono::microseconds max_latency{0};
    std::chrono::microseconds avg_latency{0};
    std::chrono::microseconds p50_latency{0};
    std::chrono::microseconds p95_latency{0};
    std::chrono::microseconds p99_latency{0};
    
    double requests_per_second() const {
        return total_time.count() > 0 ? 
               (static_cast<double>(successful_requests) * 1000000.0) / total_time.count() : 0.0;
    }
    
    double throughput_mbps() const {
        // Assuming average 80 bytes per request (key + value + protocol overhead)
        return (requests_per_second() * 80.0) / (1024.0 * 1024.0);
    }
};

// High-performance Redis client
class RedisClient {
public:
    explicit RedisClient(const std::string& host, uint16_t port) 
        : host_(host), port_(port), socket_fd_(-1) {}
    
    ~RedisClient() {
        disconnect();
    }
    
    bool connect() {
        socket_fd_ = socket(AF_INET, SOCK_STREAM, 0);
        if (socket_fd_ < 0) {
            return false;
        }
        
        // Configure socket for performance
        int nodelay = 1;
        setsockopt(socket_fd_, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));
        
        int keepalive = 1;
        setsockopt(socket_fd_, SOL_SOCKET, SO_KEEPALIVE, &keepalive, sizeof(keepalive));
        
        // Set larger buffers
        int buffer_size = 64 * 1024;
        setsockopt(socket_fd_, SOL_SOCKET, SO_RCVBUF, &buffer_size, sizeof(buffer_size));
        setsockopt(socket_fd_, SOL_SOCKET, SO_SNDBUF, &buffer_size, sizeof(buffer_size));
        
        struct sockaddr_in server_addr{};
        server_addr.sin_family = AF_INET;
        server_addr.sin_port = htons(port_);
        
        if (inet_pton(AF_INET, host_.c_str(), &server_addr.sin_addr) <= 0) {
            close(socket_fd_);
            return false;
        }
        
        if (::connect(socket_fd_, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
            close(socket_fd_);
            return false;
        }
        
        return true;
    }
    
    void disconnect() {
        if (socket_fd_ >= 0) {
            close(socket_fd_);
            socket_fd_ = -1;
        }
    }
    
    bool send_command(const std::string& command) {
        if (socket_fd_ < 0) return false;
        
        ssize_t sent = send(socket_fd_, command.c_str(), command.length(), MSG_NOSIGNAL);
        return sent == static_cast<ssize_t>(command.length());
    }
    
    std::string receive_response() {
        if (socket_fd_ < 0) return "";
        
        char buffer[4096];
        std::string response;
        
        while (true) {
            ssize_t received = recv(socket_fd_, buffer, sizeof(buffer), 0);
            if (received <= 0) break;
            
            response.append(buffer, received);
            
            // Check if we have a complete response
            if (is_complete_response(response)) {
                break;
            }
        }
        
        return response;
    }
    
    bool ping() {
        return send_command("*1\r\n$4\r\nPING\r\n") && !receive_response().empty();
    }
    
    bool set(const std::string& key, const std::string& value) {
        std::string command = "*3\r\n$3\r\nSET\r\n$" + std::to_string(key.length()) + 
                             "\r\n" + key + "\r\n$" + std::to_string(value.length()) + 
                             "\r\n" + value + "\r\n";
        return send_command(command) && !receive_response().empty();
    }
    
    std::string get(const std::string& key) {
        std::string command = "*2\r\n$3\r\nGET\r\n$" + std::to_string(key.length()) + 
                             "\r\n" + key + "\r\n";
        if (!send_command(command)) return "";
        return receive_response();
    }
    
    bool pipeline_commands(const std::vector<std::string>& commands) {
        std::string batch_command;
        for (const auto& cmd : commands) {
            batch_command += cmd;
        }
        
        if (!send_command(batch_command)) return false;
        
        // Receive all responses
        for (size_t i = 0; i < commands.size(); ++i) {
            if (receive_response().empty()) return false;
        }
        
        return true;
    }
    
private:
    std::string host_;
    uint16_t port_;
    int socket_fd_;
    
    bool is_complete_response(const std::string& response) {
        if (response.empty()) return false;
        
        // Simple RESP response detection
        if (response[0] == '+' || response[0] == '-' || response[0] == ':') {
            return response.find("\r\n") != std::string::npos;
        } else if (response[0] == '$') {
            // Bulk string
            size_t first_crlf = response.find("\r\n");
            if (first_crlf == std::string::npos) return false;
            
            int len = std::stoi(response.substr(1, first_crlf - 1));
            if (len == -1) return true; // Null response
            
            return response.length() >= first_crlf + 2 + len + 2;
        }
        
        return true;
    }
};

// Benchmark runner
class BenchmarkRunner {
public:
    explicit BenchmarkRunner(const BenchmarkConfig& config) : config_(config) {}
    
    std::vector<BenchmarkResult> run_all_benchmarks() {
        std::vector<BenchmarkResult> results;
        
        std::cout << "Starting comprehensive benchmark suite..." << std::endl;
        std::cout << "Target: " << config_.host << ":" << config_.port << std::endl;
        std::cout << "Clients: " << config_.num_clients << std::endl;
        std::cout << "Requests: " << config_.num_requests << std::endl;
        std::cout << "Pipeline size: " << config_.pipeline_size << std::endl;
        std::cout << std::endl;
        
        // Basic operation tests
        if (config_.test_ping) {
            results.push_back(run_ping_benchmark());
        }
        
        if (config_.test_set) {
            results.push_back(run_set_benchmark());
        }
        
        if (config_.test_get) {
            results.push_back(run_get_benchmark());
        }
        
        if (config_.test_mixed) {
            results.push_back(run_mixed_benchmark());
        }
        
        // Advanced tests
        if (config_.test_pipeline) {
            results.push_back(run_pipeline_benchmark());
        }
        
        if (config_.test_batch) {
            results.push_back(run_batch_benchmark());
        }
        
        if (config_.test_concurrent) {
            results.push_back(run_concurrent_benchmark());
        }
        
        // Duration-based test
        results.push_back(run_duration_benchmark());
        
        // Save results
        save_results(results);
        
        return results;
    }
    
private:
    BenchmarkConfig config_;
    
    BenchmarkResult run_ping_benchmark() {
        std::cout << "Running PING benchmark..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "PING";
        
        std::vector<std::chrono::microseconds> latencies;
        latencies.reserve(config_.num_requests);
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Create clients
        std::vector<std::unique_ptr<RedisClient>> clients;
        for (size_t i = 0; i < config_.num_clients; ++i) {
            auto client = std::make_unique<RedisClient>(config_.host, config_.port);
            if (client->connect()) {
                clients.push_back(std::move(client));
            }
        }
        
        if (clients.empty()) {
            std::cerr << "Failed to connect any clients!" << std::endl;
            return result;
        }
        
        // Run benchmark
        std::atomic<size_t> completed_requests{0};
        std::vector<std::future<void>> futures;
        
        size_t requests_per_client = config_.num_requests / clients.size();
        
        for (size_t i = 0; i < clients.size(); ++i) {
            futures.push_back(std::async(std::launch::async, [&, i]() {
                auto* client = clients[i].get();
                
                for (size_t j = 0; j < requests_per_client; ++j) {
                    auto req_start = std::chrono::high_resolution_clock::now();
                    
                    if (client->ping()) {
                        auto req_end = std::chrono::high_resolution_clock::now();
                        auto latency = std::chrono::duration_cast<std::chrono::microseconds>(req_end - req_start);
                        
                        // Thread-safe latency recording (simplified)
                        result.successful_requests++;
                        
                        if (latency < result.min_latency) result.min_latency = latency;
                        if (latency > result.max_latency) result.max_latency = latency;
                    } else {
                        result.failed_requests++;
                    }
                    
                    completed_requests++;
                }
            }));
        }
        
        // Wait for completion
        for (auto& future : futures) {
            future.wait();
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        result.total_time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time);
        result.total_requests = completed_requests.load();
        
        if (result.successful_requests > 0) {
            result.avg_latency = std::chrono::microseconds(result.total_time.count() / result.successful_requests);
        }
        
        print_result(result);
        return result;
    }
    
    BenchmarkResult run_set_benchmark() {
        std::cout << "Running SET benchmark..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "SET";
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Create clients
        std::vector<std::unique_ptr<RedisClient>> clients;
        for (size_t i = 0; i < config_.num_clients; ++i) {
            auto client = std::make_unique<RedisClient>(config_.host, config_.port);
            if (client->connect()) {
                clients.push_back(std::move(client));
            }
        }
        
        if (clients.empty()) {
            std::cerr << "Failed to connect any clients!" << std::endl;
            return result;
        }
        
        // Generate test data
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> dis(0, 255);
        
        std::vector<std::string> keys, values;
        for (size_t i = 0; i < config_.num_requests; ++i) {
            std::string key(config_.key_size, 0);
            std::string value(config_.value_size, 0);
            
            for (size_t j = 0; j < config_.key_size; ++j) {
                key[j] = 'a' + (dis(gen) % 26);
            }
            
            for (size_t j = 0; j < config_.value_size; ++j) {
                value[j] = 'A' + (dis(gen) % 26);
            }
            
            keys.push_back(key);
            values.push_back(value);
        }
        
        // Run benchmark
        std::atomic<size_t> completed_requests{0};
        std::vector<std::future<void>> futures;
        
        size_t requests_per_client = config_.num_requests / clients.size();
        
        for (size_t i = 0; i < clients.size(); ++i) {
            futures.push_back(std::async(std::launch::async, [&, i]() {
                auto* client = clients[i].get();
                
                for (size_t j = 0; j < requests_per_client; ++j) {
                    size_t key_idx = i * requests_per_client + j;
                    if (key_idx >= keys.size()) break;
                    
                    if (client->set(keys[key_idx], values[key_idx])) {
                        result.successful_requests++;
                    } else {
                        result.failed_requests++;
                    }
                    
                    completed_requests++;
                }
            }));
        }
        
        // Wait for completion
        for (auto& future : futures) {
            future.wait();
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        result.total_time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time);
        result.total_requests = completed_requests.load();
        
        if (result.successful_requests > 0) {
            result.avg_latency = std::chrono::microseconds(result.total_time.count() / result.successful_requests);
        }
        
        print_result(result);
        return result;
    }
    
    BenchmarkResult run_get_benchmark() {
        std::cout << "Running GET benchmark..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "GET";
        
        // First, populate the cache with SET operations
        std::cout << "Populating cache for GET test..." << std::endl;
        run_set_benchmark();
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Create clients
        std::vector<std::unique_ptr<RedisClient>> clients;
        for (size_t i = 0; i < config_.num_clients; ++i) {
            auto client = std::make_unique<RedisClient>(config_.host, config_.port);
            if (client->connect()) {
                clients.push_back(std::move(client));
            }
        }
        
        if (clients.empty()) {
            std::cerr << "Failed to connect any clients!" << std::endl;
            return result;
        }
        
        // Generate keys to fetch
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> dis(0, config_.num_requests - 1);
        
        std::vector<std::string> keys;
        for (size_t i = 0; i < config_.num_requests; ++i) {
            std::string key(config_.key_size, 0);
            for (size_t j = 0; j < config_.key_size; ++j) {
                key[j] = 'a' + (dis(gen) % 26);
            }
            keys.push_back(key);
        }
        
        // Run benchmark
        std::atomic<size_t> completed_requests{0};
        std::vector<std::future<void>> futures;
        
        size_t requests_per_client = config_.num_requests / clients.size();
        
        for (size_t i = 0; i < clients.size(); ++i) {
            futures.push_back(std::async(std::launch::async, [&, i]() {
                auto* client = clients[i].get();
                
                for (size_t j = 0; j < requests_per_client; ++j) {
                    size_t key_idx = i * requests_per_client + j;
                    if (key_idx >= keys.size()) break;
                    
                    std::string response = client->get(keys[key_idx]);
                    if (!response.empty()) {
                        result.successful_requests++;
                    } else {
                        result.failed_requests++;
                    }
                    
                    completed_requests++;
                }
            }));
        }
        
        // Wait for completion
        for (auto& future : futures) {
            future.wait();
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        result.total_time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - start_time);
        result.total_requests = completed_requests.load();
        
        if (result.successful_requests > 0) {
            result.avg_latency = std::chrono::microseconds(result.total_time.count() / result.successful_requests);
        }
        
        print_result(result);
        return result;
    }
    
    BenchmarkResult run_mixed_benchmark() {
        std::cout << "Running MIXED benchmark (80% GET, 20% SET)..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "MIXED";
        
        // Implementation similar to above but with mixed operations
        // ... (implementation details)
        
        return result;
    }
    
    BenchmarkResult run_pipeline_benchmark() {
        std::cout << "Running PIPELINE benchmark..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "PIPELINE";
        
        // Test pipelined operations
        // ... (implementation details)
        
        return result;
    }
    
    BenchmarkResult run_batch_benchmark() {
        std::cout << "Running BATCH benchmark..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "BATCH";
        
        // Test batch operations (MGET, MSET)
        // ... (implementation details)
        
        return result;
    }
    
    BenchmarkResult run_concurrent_benchmark() {
        std::cout << "Running CONCURRENT benchmark..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "CONCURRENT";
        
        // Test high-concurrency scenarios
        // ... (implementation details)
        
        return result;
    }
    
    BenchmarkResult run_duration_benchmark() {
        std::cout << "Running DURATION benchmark for " << config_.duration.count() << " seconds..." << std::endl;
        
        BenchmarkResult result;
        result.test_name = "DURATION";
        
        auto start_time = std::chrono::high_resolution_clock::now();
        auto end_time = start_time + config_.duration;
        
        // Run continuous load for specified duration
        // ... (implementation details)
        
        return result;
    }
    
    void print_result(const BenchmarkResult& result) {
        std::cout << std::fixed << std::setprecision(2);
        std::cout << "=== " << result.test_name << " Results ===" << std::endl;
        std::cout << "Total Requests: " << result.total_requests << std::endl;
        std::cout << "Successful: " << result.successful_requests << std::endl;
        std::cout << "Failed: " << result.failed_requests << std::endl;
        std::cout << "Duration: " << result.total_time.count() / 1000.0 << " ms" << std::endl;
        std::cout << "Requests/sec: " << result.requests_per_second() << std::endl;
        std::cout << "Throughput: " << result.throughput_mbps() << " MB/s" << std::endl;
        std::cout << "Avg Latency: " << result.avg_latency.count() << " μs" << std::endl;
        std::cout << "Min Latency: " << result.min_latency.count() << " μs" << std::endl;
        std::cout << "Max Latency: " << result.max_latency.count() << " μs" << std::endl;
        std::cout << std::endl;
    }
    
    void save_results(const std::vector<BenchmarkResult>& results) {
        std::ofstream file(config_.output_file);
        if (!file.is_open()) {
            std::cerr << "Failed to open output file: " << config_.output_file << std::endl;
            return;
        }
        
        // CSV header
        file << "Test,Total_Requests,Successful_Requests,Failed_Requests,Duration_ms,";
        file << "Requests_Per_Second,Throughput_MBps,Avg_Latency_us,Min_Latency_us,Max_Latency_us\n";
        
        // CSV data
        for (const auto& result : results) {
            file << result.test_name << ","
                 << result.total_requests << ","
                 << result.successful_requests << ","
                 << result.failed_requests << ","
                 << result.total_time.count() / 1000.0 << ","
                 << result.requests_per_second() << ","
                 << result.throughput_mbps() << ","
                 << result.avg_latency.count() << ","
                 << result.min_latency.count() << ","
                 << result.max_latency.count() << "\n";
        }
        
        file.close();
        std::cout << "Results saved to: " << config_.output_file << std::endl;
    }
};

// Main benchmark application
int main(int argc, char* argv[]) {
    BenchmarkConfig config;
    
    // Parse command line arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        
        if (arg == "--host" && i + 1 < argc) {
            config.host = argv[++i];
        } else if (arg == "--port" && i + 1 < argc) {
            config.port = static_cast<uint16_t>(std::stoi(argv[++i]));
        } else if (arg == "--clients" && i + 1 < argc) {
            config.num_clients = std::stoul(argv[++i]);
        } else if (arg == "--requests" && i + 1 < argc) {
            config.num_requests = std::stoul(argv[++i]);
        } else if (arg == "--pipeline" && i + 1 < argc) {
            config.pipeline_size = std::stoul(argv[++i]);
        } else if (arg == "--output" && i + 1 < argc) {
            config.output_file = argv[++i];
        } else if (arg == "--duration" && i + 1 < argc) {
            config.duration = std::chrono::seconds(std::stoi(argv[++i]));
        } else if (arg == "--verbose") {
            config.verbose = true;
        } else if (arg == "--help") {
            std::cout << "Usage: " << argv[0] << " [OPTIONS]\n"
                      << "Options:\n"
                      << "  --host HOST        Server host (default: localhost)\n"
                      << "  --port PORT        Server port (default: 6379)\n"
                      << "  --clients N        Number of clients (default: 50)\n"
                      << "  --requests N       Number of requests (default: 100000)\n"
                      << "  --pipeline N       Pipeline size (default: 10)\n"
                      << "  --duration N       Duration test seconds (default: 30)\n"
                      << "  --output FILE      Output CSV file (default: benchmark_results.csv)\n"
                      << "  --verbose          Enable verbose output\n"
                      << "  --help             Show this help\n";
            return 0;
        }
    }
    
    try {
        BenchmarkRunner runner(config);
        auto results = runner.run_all_benchmarks();
        
        // Print summary
        std::cout << "\n=== BENCHMARK SUMMARY ===" << std::endl;
        for (const auto& result : results) {
            std::cout << std::left << std::setw(15) << result.test_name 
                      << std::right << std::setw(12) << std::fixed << std::setprecision(2) 
                      << result.requests_per_second() << " req/s" << std::endl;
        }
        
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Benchmark failed: " << e.what() << std::endl;
        return 1;
    }
} 