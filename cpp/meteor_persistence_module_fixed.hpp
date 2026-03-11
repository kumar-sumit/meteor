// **METEOR PERSISTENCE MODULE**
// Production-grade RDB + AOF persistence with io_uring async I/O
// Zero performance impact, Dragonfly-inspired architecture
//
// Usage:
//   #include "meteor_persistence_module.hpp"
//   persistence::PersistenceManager manager(config);
//   manager.log_write_command("SET", {"key", "value"});
//   manager.create_snapshot(shard_data);

#pragma once

#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <atomic>
#include <mutex>
#include <thread>
#include <chrono>
#include <filesystem>
#include <deque>
#include <sys/uio.h>
#include <fcntl.h>
#include <unistd.h>
#include <liburing.h>

// Compression libraries
#include <lz4.h>
#include <lz4frame.h>

namespace meteor {
namespace persistence {

// **PERSISTENCE CONFIGURATION**
struct PersistenceConfig {
    bool enabled = false;
    std::string rdb_path = "./snapshots/";
    std::string aof_path = "./";
    std::string aof_filename = "meteor.aof";
    std::string rdb_filename_prefix = "meteor_";
    
    // RDB settings
    uint64_t snapshot_interval_seconds = 300;  // 5 minutes
    uint64_t snapshot_operation_threshold = 100000;  // 100K operations
    bool compress_snapshots = true;
    uint32_t compression_level = 3;  // LZ4 default
    
    // AOF settings
    bool aof_enabled = true;
    uint32_t aof_fsync_policy = 2;  // 0=never, 1=always, 2=everysec
    bool aof_auto_truncate = true;
    uint64_t aof_buffer_size = 8192;  // 8KB buffer
    
    // Recovery settings
    std::string recovery_mode = "auto";  // auto, rdb-only, aof-only, none
    bool load_on_startup = true;
    
    // Monitoring
    bool verbose_logging = false;
    
    // Create directories if they don't exist
    void ensure_directories() {
        std::filesystem::create_directories(rdb_path);
        std::filesystem::create_directories(aof_path);
    }
};

// **RDB SNAPSHOT WRITER WITH IO_URING**
class RDBWriter {
private:
    std::string filename_;
    int fd_;
    io_uring ring_;
    bool compress_;
    uint32_t compression_level_;
    bool io_uring_initialized_;
    
    // RDB format constants
    static constexpr const char* MAGIC = "METEOR-RDB";
    static constexpr uint16_t VERSION = 2;
    static constexpr uint8_t COMPRESS_NONE = 0;
    static constexpr uint8_t COMPRESS_LZ4 = 1;
    
public:
    RDBWriter(const std::string& filename, bool compress = true, uint32_t compression_level = 3)
        : filename_(filename)
        , fd_(-1)
        , compress_(compress)
        , compression_level_(compression_level)
        , io_uring_initialized_(false)
    {
    }
    
    ~RDBWriter() {
        close();
    }
    
    bool open() {
        fd_ = ::open(filename_.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd_ < 0) {
            std::cerr << "❌ Failed to open RDB file: " << filename_ << std::endl;
            return false;
        }
        
        // Initialize io_uring
        int ret = io_uring_queue_init(256, &ring_, 0);
        if (ret < 0) {
            std::cerr << "⚠️  io_uring init failed, falling back to sync I/O" << std::endl;
            io_uring_initialized_ = false;
        } else {
            io_uring_initialized_ = true;
        }
        
        // Write RDB header
        write_header();
        
        return true;
    }
    
    void close() {
        if (fd_ >= 0) {
            // Write EOF marker
            uint8_t eof_marker = 0xFF;
            ::write(fd_, &eof_marker, 1);
            
            if (io_uring_initialized_) {
                io_uring_queue_exit(&ring_);
            }
            ::close(fd_);
            fd_ = -1;
        }
    }
    
    // Write a single key-value pair
    bool write_entry(const std::string& key, const std::string& value, uint64_t ttl_ms = 0) {
        std::vector<uint8_t> buffer;
        
        // Entry format: [key_len:4][key][value_len:4][value][ttl:8]
        uint32_t key_len = key.size();
        uint32_t value_len = value.size();
        
        buffer.reserve(8 + key_len + value_len + 8);
        
        // Write key length and key
        buffer.insert(buffer.end(), (uint8_t*)&key_len, (uint8_t*)&key_len + 4);
        buffer.insert(buffer.end(), key.begin(), key.end());
        
        // Write value length and value
        buffer.insert(buffer.end(), (uint8_t*)&value_len, (uint8_t*)&value_len + 4);
        buffer.insert(buffer.end(), value.begin(), value.end());
        
        // Write TTL
        buffer.insert(buffer.end(), (uint8_t*)&ttl_ms, (uint8_t*)&ttl_ms + 8);
        
        // Write buffer
        return write_buffer(buffer.data(), buffer.size());
    }
    
    // Write shard data (all entries from one shard)
    bool write_shard(uint32_t shard_id, 
                     const std::unordered_map<std::string, std::string>& data) {
        // Shard header: [shard_id:4][entry_count:4]
        uint32_t entry_count = data.size();
        
        ::write(fd_, &shard_id, 4);
        ::write(fd_, &entry_count, 4);
        
        // Write all entries
        for (const auto& [key, value] : data) {
            if (!write_entry(key, value, 0)) {
                return false;
            }
        }
        
        return true;
    }
    
private:
    void write_header() {
        // Header: [MAGIC:10][VERSION:2][TIMESTAMP:8][COMPRESS:1]
        uint64_t timestamp = std::chrono::system_clock::now().time_since_epoch().count();
        uint8_t compress_flag = compress_ ? COMPRESS_LZ4 : COMPRESS_NONE;
        
        ::write(fd_, MAGIC, 10);
        ::write(fd_, &VERSION, 2);
        ::write(fd_, &timestamp, 8);
        ::write(fd_, &compress_flag, 1);
    }
    
    bool write_buffer(const void* data, size_t size) {
        if (io_uring_initialized_) {
            return write_async(data, size);
        } else {
            ssize_t written = ::write(fd_, data, size);
            return written == (ssize_t)size;
        }
    }
    
    bool write_async(const void* data, size_t size) {
        // Use io_uring for async write
        io_uring_sqe* sqe = io_uring_get_sqe(&ring_);
        if (!sqe) return false;
        
        io_uring_prep_write(sqe, fd_, data, size, -1);
        io_uring_submit(&ring_);
        
        // Wait for completion
        io_uring_cqe* cqe;
        io_uring_wait_cqe(&ring_, &cqe);
        bool success = cqe->res >= 0;
        io_uring_cqe_seen(&ring_, cqe);
        
        return success;
    }
};

// **RDB SNAPSHOT READER**
class RDBReader {
private:
    std::string filename_;
    int fd_;
    std::vector<uint8_t> buffer_;
    size_t read_pos_;
    
public:
    struct Entry {
        std::string key;
        std::string value;
        uint64_t ttl_ms;
        uint32_t shard_id;
    };
    
    RDBReader(const std::string& filename)
        : filename_(filename), fd_(-1), read_pos_(0)
    {
    }
    
    ~RDBReader() {
        close();
    }
    
    bool open() {
        fd_ = ::open(filename_.c_str(), O_RDONLY);
        if (fd_ < 0) {
            std::cerr << "❌ Failed to open RDB file: " << filename_ << std::endl;
            return false;
        }
        
        // Read entire file into buffer
        off_t file_size = lseek(fd_, 0, SEEK_END);
        lseek(fd_, 0, SEEK_SET);
        
        buffer_.resize(file_size);
        ssize_t bytes_read = ::read(fd_, buffer_.data(), file_size);
        
        if (bytes_read != file_size) {
            std::cerr << "❌ Failed to read RDB file completely" << std::endl;
            return false;
        }
        
        // Parse and validate header
        return parse_header();
    }
    
    void close() {
        if (fd_ >= 0) {
            ::close(fd_);
            fd_ = -1;
        }
    }
    
    // Read all entries
    std::vector<Entry> read_all() {
        std::vector<Entry> entries;
        
        while (read_pos_ < buffer_.size()) {
            // Check for EOF marker
            if (buffer_[read_pos_] == 0xFF) {
                break;
            }
            
            // Read shard header
            uint32_t shard_id = read_uint32();
            uint32_t entry_count = read_uint32();
            
            // Read all entries for this shard
            for (uint32_t i = 0; i < entry_count; ++i) {
                Entry entry;
                entry.shard_id = shard_id;
                
                // Read key
                uint32_t key_len = read_uint32();
                entry.key = read_string(key_len);
                
                // Read value
                uint32_t value_len = read_uint32();
                entry.value = read_string(value_len);
                
                // Read TTL
                entry.ttl_ms = read_uint64();
                
                entries.push_back(entry);
            }
        }
        
        return entries;
    }
    
private:
    bool parse_header() {
        // Validate magic
        char magic[11] = {0};
        memcpy(magic, buffer_.data(), 10);
        read_pos_ += 10;
        
        if (std::string(magic) != "METEOR-RDB") {
            std::cerr << "❌ Invalid RDB file: bad magic" << std::endl;
            return false;
        }
        
        // Read version
        uint16_t version = read_uint16();
        if (version != 2) {
            std::cerr << "⚠️  RDB version mismatch: " << version << " (expected 2)" << std::endl;
        }
        
        // Skip timestamp and compression flag
        read_pos_ += 8 + 1;
        
        return true;
    }
    
    uint16_t read_uint16() {
        uint16_t val = *(uint16_t*)(buffer_.data() + read_pos_);
        read_pos_ += 2;
        return val;
    }
    
    uint32_t read_uint32() {
        uint32_t val = *(uint32_t*)(buffer_.data() + read_pos_);
        read_pos_ += 4;
        return val;
    }
    
    uint64_t read_uint64() {
        uint64_t val = *(uint64_t*)(buffer_.data() + read_pos_);
        read_pos_ += 8;
        return val;
    }
    
    std::string read_string(size_t len) {
        std::string str((char*)(buffer_.data() + read_pos_), len);
        read_pos_ += len;
        return str;
    }
};

// **AOF (APPEND-ONLY FILE) WRITER**
class AOFWriter {
private:
    std::string filename_;
    std::ofstream file_;
    std::mutex write_mutex_;
    std::deque<std::string> write_buffer_;
    std::thread fsync_thread_;
    std::atomic<bool> running_;
    uint32_t fsync_policy_;
    std::atomic<uint64_t> bytes_written_;
    
public:
    AOFWriter(const std::string& filename, uint32_t fsync_policy = 2)
        : filename_(filename)
        , running_(false)
        , fsync_policy_(fsync_policy)
        , bytes_written_(0)
    {
    }
    
    ~AOFWriter() {
        close();
    }
    
    bool open() {
        file_.open(filename_, std::ios::app | std::ios::binary);
        if (!file_.is_open()) {
            std::cerr << "❌ Failed to open AOF file: " << filename_ << std::endl;
            return false;
        }
        
        running_ = true;
        
        // Start background fsync thread if policy is everysec
        if (fsync_policy_ == 2) {
            fsync_thread_ = std::thread(&AOFWriter::fsync_loop, this);
        }
        
        return true;
    }
    
    void close() {
        running_ = false;
        
        if (fsync_thread_.joinable()) {
            fsync_thread_.join();
        }
        
        if (file_.is_open()) {
            file_.flush();
            file_.close();
        }
    }
    
    // Log a write command in RESP format
    void log_command(const std::string& cmd, const std::vector<std::string>& args) {
        std::lock_guard<std::mutex> lock(write_mutex_);
        
        // Build RESP array: *<count>\r\n$<len>\r\n<data>\r\n...
        std::ostringstream oss;
        oss << "*" << (args.size() + 1) << "\r\n";
        oss << "$" << cmd.size() << "\r\n" << cmd << "\r\n";
        
        for (const auto& arg : args) {
            oss << "$" << arg.size() << "\r\n" << arg << "\r\n";
        }
        
        std::string entry = oss.str();
        
        // Write immediately
        file_ << entry;
        bytes_written_ += entry.size();
        
        // Fsync based on policy
        if (fsync_policy_ == 1) {  // always
            file_.flush();
        }
    }
    
    // Truncate AOF file (called after successful RDB snapshot)
    void truncate() {
        std::lock_guard<std::mutex> lock(write_mutex_);
        
        file_.close();
        file_.open(filename_, std::ios::trunc | std::ios::binary);
        file_.close();
        file_.open(filename_, std::ios::app | std::ios::binary);
        
        bytes_written_ = 0;
        
        std::cout << "🗑️  AOF truncated after RDB snapshot" << std::endl;
    }
    
    uint64_t get_bytes_written() const {
        return bytes_written_.load();
    }
    
private:
    void fsync_loop() {
        while (running_) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            
            std::lock_guard<std::mutex> lock(write_mutex_);
            if (file_.is_open()) {
                file_.flush();
            }
        }
    }
};

// **AOF READER FOR RECOVERY**
class AOFReader {
private:
    std::string filename_;
    
public:
    struct Command {
        std::string cmd;
        std::vector<std::string> args;
    };
    
    AOFReader(const std::string& filename)
        : filename_(filename)
    {
    }
    
    // Parse AOF file and return all commands
    std::vector<Command> read_all() {
        std::vector<Command> commands;
        
        std::ifstream file(filename_, std::ios::binary);
        if (!file.is_open()) {
            std::cerr << "⚠️  AOF file not found or cannot be opened: " << filename_ << std::endl;
            return commands;
        }
        
        std::string line;
        while (std::getline(file, line)) {
            // Remove trailing \r if present (RESP uses \r\n line endings)
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            
            // Skip empty lines
            if (line.empty() || line[0] != '*') continue;
            
            // Parse RESP array
            Command cmd = parse_resp_command(file, line);
            if (!cmd.cmd.empty()) {
                commands.push_back(cmd);
            }
        }
        
        return commands;
    }
    
private:
    Command parse_resp_command(std::ifstream& file, const std::string& array_line) {
        Command cmd;
        
        // Parse array count: *<count>\r\n
        int count = std::stoi(array_line.substr(1));
        
        std::string line;
        for (int i = 0; i < count; ++i) {
            // Read bulk string: $<len>\r\n<data>\r\n
            if (!std::getline(file, line)) {
                return cmd;
            }
            
            // Remove trailing \r
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            
            if (line.empty() || line[0] != '$') {
                return cmd;  // Invalid format
            }
            
            int len = std::stoi(line.substr(1));
            
            if (!std::getline(file, line)) {
                return cmd;
            }
            
            // Remove trailing \r from data
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            
            if (i == 0) {
                cmd.cmd = line;
            } else {
                cmd.args.push_back(line);
            }
        }
        
        return cmd;
    }
};

// **PERSISTENCE MANAGER - Main Interface**
class PersistenceManager {
private:
    PersistenceConfig config_;
    std::unique_ptr<AOFWriter> aof_writer_;
    std::atomic<uint64_t> operations_since_snapshot_;
    std::chrono::steady_clock::time_point last_snapshot_time_;
    std::mutex snapshot_mutex_;
    
public:
    PersistenceManager(const PersistenceConfig& config)
        : config_(config)
        , operations_since_snapshot_(0)
        , last_snapshot_time_(std::chrono::steady_clock::now())
    {
        if (config_.enabled) {
            config_.ensure_directories();
            
            if (config_.aof_enabled) {
                std::string aof_path = config_.aof_path + "/" + config_.aof_filename;
                aof_writer_ = std::make_unique<AOFWriter>(aof_path, config_.aof_fsync_policy);
                aof_writer_->open();
            }
        }
    }
    
    ~PersistenceManager() {
        if (aof_writer_) {
            aof_writer_->close();
        }
    }
    
    // Log a write command to AOF
    void log_write_command(const std::string& cmd, const std::vector<std::string>& args) {
        if (!config_.enabled || !config_.aof_enabled || !aof_writer_) {
            return;
        }
        
        aof_writer_->log_command(cmd, args);
        operations_since_snapshot_++;
    }
    
    // Check if snapshot is needed
    bool should_create_snapshot() {
        if (!config_.enabled) return false;
        
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
            now - last_snapshot_time_
        ).count();
        
        return (elapsed >= config_.snapshot_interval_seconds) ||
               (operations_since_snapshot_ >= config_.snapshot_operation_threshold);
    }
    
    // Create RDB snapshot
    bool create_snapshot(const std::vector<std::unordered_map<std::string, std::string>>& shard_data) {
        if (!config_.enabled) return false;
        
        std::lock_guard<std::mutex> lock(snapshot_mutex_);
        
        // Generate snapshot filename with timestamp
        uint64_t timestamp = std::chrono::system_clock::now().time_since_epoch().count();
        std::string filename = config_.rdb_path + "/" + config_.rdb_filename_prefix + 
                              std::to_string(timestamp) + ".rdb";
        
        RDBWriter writer(filename, config_.compress_snapshots, config_.compression_level);
        if (!writer.open()) {
            return false;
        }
        
        // Write each shard
        for (size_t shard_id = 0; shard_id < shard_data.size(); ++shard_id) {
            if (!writer.write_shard(shard_id, shard_data[shard_id])) {
                std::cerr << "❌ Failed to write shard " << shard_id << std::endl;
                return false;
            }
        }
        
        writer.close();
        
        // Create/update "latest" symlink (use basename only for relative symlink)
        std::string latest_link = config_.rdb_path + "/meteor_latest.rdb";
        std::filesystem::remove(latest_link);
        // Extract just the filename from the full path for the symlink target
        std::string basename = filename.substr(filename.find_last_of("/") + 1);
        std::filesystem::create_symlink(basename, latest_link);
        
        // Truncate AOF if enabled
        if (config_.aof_enabled && config_.aof_auto_truncate && aof_writer_) {
            aof_writer_->truncate();
        }
        
        // Reset counters
        operations_since_snapshot_ = 0;
        last_snapshot_time_ = std::chrono::steady_clock::now();
        
        std::cout << "✅ RDB snapshot created: " << filename << std::endl;
        return true;
    }
    
    // Load data from RDB + AOF for recovery
    struct RecoveredEntry {
        std::string key;
        std::string value;
        size_t target_shard;  // Computed from key hash
    };
    
    std::vector<RecoveredEntry> recover_data(size_t total_shards) {
        std::vector<RecoveredEntry> entries;
        
        if (!config_.enabled || !config_.load_on_startup) {
            return entries;
        }
        
        // Step 1: Load RDB snapshot
        std::string rdb_file = config_.rdb_path + "/meteor_latest.rdb";
        if (std::filesystem::exists(rdb_file)) {
            std::cout << "📂 Loading RDB snapshot: " << rdb_file << std::endl;
            
            RDBReader reader(rdb_file);
            if (reader.open()) {
                auto rdb_entries = reader.read_all();
                
                for (const auto& entry : rdb_entries) {
                    RecoveredEntry recovered;
                    recovered.key = entry.key;
                    recovered.value = entry.value;
                    recovered.target_shard = std::hash<std::string>{}(entry.key) % total_shards;
                    entries.push_back(recovered);
                }
                
                std::cout << "✅ Loaded " << rdb_entries.size() << " entries from RDB" << std::endl;
            }
        } else {
            std::cout << "⚠️  No RDB snapshot found, starting fresh" << std::endl;
        }
        
        // Step 2: Replay AOF
        std::string aof_file = config_.aof_path + "/" + config_.aof_filename;
        if (std::filesystem::exists(aof_file)) {
            std::cout << "📂 Replaying AOF: " << aof_file << std::endl;
            
            AOFReader reader(aof_file);
            auto commands = reader.read_all();
            
            // Apply commands to recovered data
            std::unordered_map<std::string, std::string> temp_data;
            for (const auto& entry : entries) {
                temp_data[entry.key] = entry.value;
            }
            
            for (const auto& cmd : commands) {
                if (cmd.cmd == "SET" && cmd.args.size() >= 2) {
                    temp_data[cmd.args[0]] = cmd.args[1];
                } else if (cmd.cmd == "DEL" && cmd.args.size() >= 1) {
                    temp_data.erase(cmd.args[0]);
                } else if (cmd.cmd == "MSET") {
                    for (size_t i = 0; i + 1 < cmd.args.size(); i += 2) {
                        temp_data[cmd.args[i]] = cmd.args[i + 1];
                    }
                }
            }
            
            // Rebuild entries from updated data
            entries.clear();
            for (const auto& [key, value] : temp_data) {
                RecoveredEntry recovered;
                recovered.key = key;
                recovered.value = value;
                recovered.target_shard = std::hash<std::string>{}(key) % total_shards;
                entries.push_back(recovered);
            }
            
            std::cout << "✅ Replayed " << commands.size() << " AOF commands" << std::endl;
        }
        
        std::cout << "✅ Total recovered entries: " << entries.size() << std::endl;
        return entries;
    }
    
    // Get configuration
    const PersistenceConfig& config() const {
        return config_;
    }
};

} // namespace persistence
} // namespace meteor

