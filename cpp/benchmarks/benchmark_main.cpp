#include <iostream>
#include <chrono>
#include <thread>
#include <vector>
#include <random>
#include <atomic>
#include <memory>
#include <string>
#include <future>
#include <algorithm>
#include <fstream>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

class RedisBenchmark {
public:
    struct BenchmarkConfig {
        std::string host = "localhost";
        int port = 6379;
        int num_clients = 10;
        int num_requests = 10000;
        int pipeline_size = 1;
        int key_size = 10;
        int value_size = 100;
        bool enable_logging = false;
        std::string test_name = "SET";
    };
    
    struct BenchmarkResult {
        double total_time_seconds = 0.0;
        double requests_per_second = 0.0;
        double avg_latency_ms = 0.0;
        double min_latency_ms = 0.0;
        double max_latency_ms = 0.0;
        double p50_latency_ms = 0.0;
        double p95_latency_ms = 0.0;
        double p99_latency_ms = 0.0;
        int total_requests = 0;
        int successful_requests = 0;
        int failed_requests = 0;
        uint64_t total_bytes_sent = 0;
        uint64_t total_bytes_received = 0;
    };
    
    explicit RedisBenchmark(const BenchmarkConfig& config) : config_(config) {}
    
    BenchmarkResult run_benchmark() {
        std::cout << "Starting benchmark: " << config_.test_name 
                  << " against " << config_.host << ":" << config_.port << std::endl;
        std::cout << "Clients: " << config_.num_clients 
                  << ", Requests: " << config_.num_requests 
                  << ", Pipeline: " << config_.pipeline_size << std::endl;
        
        // Initialize result
        BenchmarkResult result;
        result.total_requests = config_.num_requests;
        
        // Prepare client threads
        std::vector<std::future<ClientResult>> futures;
        int requests_per_client = config_.num_requests / config_.num_clients;
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Launch client threads
        for (int i = 0; i < config_.num_clients; ++i) {
            int client_requests = requests_per_client;
            if (i == config_.num_clients - 1) {
                // Last client handles remaining requests
                client_requests += config_.num_requests % config_.num_clients;
            }
            
            futures.push_back(std::async(std::launch::async, 
                                       &RedisBenchmark::run_client, this, i, client_requests));
        }
        
        // Collect results
        std::vector<double> all_latencies;
        for (auto& future : futures) {
            auto client_result = future.get();
            result.successful_requests += client_result.successful_requests;
            result.failed_requests += client_result.failed_requests;
            result.total_bytes_sent += client_result.bytes_sent;
            result.total_bytes_received += client_result.bytes_received;
            
            all_latencies.insert(all_latencies.end(), 
                               client_result.latencies.begin(), 
                               client_result.latencies.end());
        }
        
        auto end_time = std::chrono::high_resolution_clock::now();
        result.total_time_seconds = std::chrono::duration<double>(end_time - start_time).count();
        
        // Calculate statistics
        if (!all_latencies.empty()) {
            std::sort(all_latencies.begin(), all_latencies.end());
            
            result.requests_per_second = result.successful_requests / result.total_time_seconds;
            result.avg_latency_ms = std::accumulate(all_latencies.begin(), all_latencies.end(), 0.0) / all_latencies.size();
            result.min_latency_ms = all_latencies.front();
            result.max_latency_ms = all_latencies.back();
            
            size_t p50_idx = all_latencies.size() * 0.5;
            size_t p95_idx = all_latencies.size() * 0.95;
            size_t p99_idx = all_latencies.size() * 0.99;
            
            result.p50_latency_ms = all_latencies[p50_idx];
            result.p95_latency_ms = all_latencies[p95_idx];
            result.p99_latency_ms = all_latencies[p99_idx];
        }
        
        return result;
    }
    
    void print_result(const BenchmarkResult& result) {
        std::cout << "\n" << std::string(60, '=') << std::endl;
        std::cout << "BENCHMARK RESULTS - " << config_.test_name << std::endl;
        std::cout << std::string(60, '=') << std::endl;
        
        std::cout << "Total time: " << result.total_time_seconds << " seconds" << std::endl;
        std::cout << "Requests per second: " << result.requests_per_second << std::endl;
        std::cout << "Successful requests: " << result.successful_requests << std::endl;
        std::cout << "Failed requests: " << result.failed_requests << std::endl;
        std::cout << "Success rate: " << (100.0 * result.successful_requests / result.total_requests) << "%" << std::endl;
        
        std::cout << "\nLatency (ms):" << std::endl;
        std::cout << "  Average: " << result.avg_latency_ms << std::endl;
        std::cout << "  Min: " << result.min_latency_ms << std::endl;
        std::cout << "  Max: " << result.max_latency_ms << std::endl;
        std::cout << "  P50: " << result.p50_latency_ms << std::endl;
        std::cout << "  P95: " << result.p95_latency_ms << std::endl;
        std::cout << "  P99: " << result.p99_latency_ms << std::endl;
        
        std::cout << "\nThroughput:" << std::endl;
        std::cout << "  Bytes sent: " << result.total_bytes_sent << std::endl;
        std::cout << "  Bytes received: " << result.total_bytes_received << std::endl;
        std::cout << "  Total bytes: " << (result.total_bytes_sent + result.total_bytes_received) << std::endl;
        
        double mbps_sent = (result.total_bytes_sent / (1024.0 * 1024.0)) / result.total_time_seconds;
        double mbps_received = (result.total_bytes_received / (1024.0 * 1024.0)) / result.total_time_seconds;
        std::cout << "  Send rate: " << mbps_sent << " MB/s" << std::endl;
        std::cout << "  Receive rate: " << mbps_received << " MB/s" << std::endl;
        
        std::cout << std::string(60, '=') << std::endl;
    }
    
    void save_csv_result(const BenchmarkResult& result, const std::string& filename) {
        std::ofstream file(filename, std::ios::app);
        if (file.is_open()) {
            // Write header if file is empty
            file.seekp(0, std::ios::end);
            if (file.tellp() == 0) {
                file << "test_name,host,port,clients,requests,pipeline,rps,avg_latency_ms,p50_latency_ms,p95_latency_ms,p99_latency_ms,success_rate\n";
            }
            
            file << config_.test_name << ","
                 << config_.host << ","
                 << config_.port << ","
                 << config_.num_clients << ","
                 << config_.num_requests << ","
                 << config_.pipeline_size << ","
                 << result.requests_per_second << ","
                 << result.avg_latency_ms << ","
                 << result.p50_latency_ms << ","
                 << result.p95_latency_ms << ","
                 << result.p99_latency_ms << ","
                 << (100.0 * result.successful_requests / result.total_requests) << "\n";
        }
    }

private:
    struct ClientResult {
        int successful_requests = 0;
        int failed_requests = 0;
        uint64_t bytes_sent = 0;
        uint64_t bytes_received = 0;
        std::vector<double> latencies;
    };
    
    ClientResult run_client(int client_id, int num_requests) {
        ClientResult result;
        result.latencies.reserve(num_requests);
        
        // Connect to server
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) {
            result.failed_requests = num_requests;
            return result;
        }
        
        struct sockaddr_in server_addr{};
        server_addr.sin_family = AF_INET;
        server_addr.sin_port = htons(config_.port);
        inet_pton(AF_INET, config_.host.c_str(), &server_addr.sin_addr);
        
        if (connect(sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
            close(sock);
            result.failed_requests = num_requests;
            return result;
        }
        
        // Generate random data
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> dis(0, 255);
        
        // Run requests
        for (int i = 0; i < num_requests; ++i) {
            auto start_time = std::chrono::high_resolution_clock::now();
            
            if (send_request(sock, client_id, i, gen, dis)) {
                if (receive_response(sock)) {
                    result.successful_requests++;
                    
                    auto end_time = std::chrono::high_resolution_clock::now();
                    double latency_ms = std::chrono::duration<double, std::milli>(end_time - start_time).count();
                    result.latencies.push_back(latency_ms);
                } else {
                    result.failed_requests++;
                }
            } else {
                result.failed_requests++;
            }
        }
        
        close(sock);
        return result;
    }
    
    bool send_request(int sock, int client_id, int request_id, std::mt19937& gen, std::uniform_int_distribution<>& dis) {
        std::string command;
        
        if (config_.test_name == "SET") {
            std::string key = "key:" + std::to_string(client_id) + ":" + std::to_string(request_id);
            std::string value = generate_random_string(config_.value_size, gen, dis);
            
            command = "*3\r\n$3\r\nSET\r\n$" + std::to_string(key.length()) + "\r\n" + key + "\r\n$" + 
                     std::to_string(value.length()) + "\r\n" + value + "\r\n";
        } else if (config_.test_name == "GET") {
            std::string key = "key:" + std::to_string(client_id) + ":" + std::to_string(request_id % 1000);
            
            command = "*2\r\n$3\r\nGET\r\n$" + std::to_string(key.length()) + "\r\n" + key + "\r\n";
        } else if (config_.test_name == "PING") {
            command = "*1\r\n$4\r\nPING\r\n";
        }
        
        ssize_t bytes_sent = send(sock, command.c_str(), command.length(), 0);
        return bytes_sent == static_cast<ssize_t>(command.length());
    }
    
    bool receive_response(int sock) {
        char buffer[4096];
        ssize_t bytes_received = recv(sock, buffer, sizeof(buffer) - 1, 0);
        
        if (bytes_received <= 0) {
            return false;
        }
        
        buffer[bytes_received] = '\0';
        
        // Simple response validation
        if (config_.test_name == "SET") {
            return strstr(buffer, "+OK") != nullptr;
        } else if (config_.test_name == "PING") {
            return strstr(buffer, "+PONG") != nullptr || strstr(buffer, "$4\r\nPONG") != nullptr;
        }
        
        return true; // For GET and other commands
    }
    
    std::string generate_random_string(size_t length, std::mt19937& gen, std::uniform_int_distribution<>& dis) {
        std::string result;
        result.reserve(length);
        
        for (size_t i = 0; i < length; ++i) {
            result.push_back(static_cast<char>(dis(gen) % 94 + 33)); // Printable ASCII
        }
        
        return result;
    }
    
    BenchmarkConfig config_;
};

void print_usage(const char* program_name) {
    std::cout << "Usage: " << program_name << " [OPTIONS]\n"
              << "Options:\n"
              << "  --host HOST              Server host (default: localhost)\n"
              << "  --port PORT              Server port (default: 6379)\n"
              << "  --clients N              Number of concurrent clients (default: 10)\n"
              << "  --requests N             Total number of requests (default: 10000)\n"
              << "  --pipeline N             Pipeline size (default: 1)\n"
              << "  --key-size N             Key size in bytes (default: 10)\n"
              << "  --value-size N           Value size in bytes (default: 100)\n"
              << "  --test TEST              Test type: SET, GET, PING (default: SET)\n"
              << "  --csv-output FILE        Save results to CSV file\n"
              << "  --enable-logging         Enable verbose logging\n"
              << "  --help                   Show this help message\n"
              << "\n"
              << "Examples:\n"
              << "  " << program_name << " --host localhost --port 6379 --test SET\n"
              << "  " << program_name << " --clients 50 --requests 100000 --test GET\n"
              << "  " << program_name << " --pipeline 10 --csv-output results.csv\n"
              << std::endl;
}

int main(int argc, char* argv[]) {
    RedisBenchmark::BenchmarkConfig config;
    std::string csv_output;
    
    // Parse command line arguments
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        
        if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        } else if (arg == "--host" && i + 1 < argc) {
            config.host = argv[++i];
        } else if (arg == "--port" && i + 1 < argc) {
            config.port = std::stoi(argv[++i]);
        } else if (arg == "--clients" && i + 1 < argc) {
            config.num_clients = std::stoi(argv[++i]);
        } else if (arg == "--requests" && i + 1 < argc) {
            config.num_requests = std::stoi(argv[++i]);
        } else if (arg == "--pipeline" && i + 1 < argc) {
            config.pipeline_size = std::stoi(argv[++i]);
        } else if (arg == "--key-size" && i + 1 < argc) {
            config.key_size = std::stoi(argv[++i]);
        } else if (arg == "--value-size" && i + 1 < argc) {
            config.value_size = std::stoi(argv[++i]);
        } else if (arg == "--test" && i + 1 < argc) {
            config.test_name = argv[++i];
        } else if (arg == "--csv-output" && i + 1 < argc) {
            csv_output = argv[++i];
        } else if (arg == "--enable-logging") {
            config.enable_logging = true;
        } else {
            std::cerr << "Unknown option: " << arg << std::endl;
            print_usage(argv[0]);
            return 1;
        }
    }
    
    try {
        RedisBenchmark benchmark(config);
        auto result = benchmark.run_benchmark();
        
        benchmark.print_result(result);
        
        if (!csv_output.empty()) {
            benchmark.save_csv_result(result, csv_output);
            std::cout << "Results saved to: " << csv_output << std::endl;
        }
        
        return 0;
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
} 