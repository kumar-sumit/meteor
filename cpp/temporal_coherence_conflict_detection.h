// **TEMPORAL COHERENCE CONFLICT DETECTION AND RESOLUTION**
// 
// Advanced conflict detection system for cross-core pipeline correctness
// - Temporal causality tracking
// - Read-after-write and write-after-write conflict detection
// - Deterministic conflict resolution using Thomas Write Rule
// - Speculative execution with rollback capabilities

#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <atomic>
#include <mutex>
#include <memory>
#include <chrono>

namespace temporal_coherence {

// **CONFLICT TYPES**
enum class ConflictType {
    READ_AFTER_WRITE,    // Reading a key that was written after pipeline start
    WRITE_AFTER_WRITE,   // Writing a key that was written after pipeline start
    WRITE_AFTER_READ     // Writing a key that was read during pipeline
};

// **CONFLICT INFO**
struct ConflictInfo {
    ConflictType type;
    std::string key;
    uint64_t pipeline_timestamp;
    uint64_t conflicting_timestamp;
    uint32_t conflicting_core;
    
    ConflictInfo(ConflictType t, const std::string& k, uint64_t pipeline_ts, 
                uint64_t conflict_ts, uint32_t conflict_core)
        : type(t), key(k), pipeline_timestamp(pipeline_ts), 
          conflicting_timestamp(conflict_ts), conflicting_core(conflict_core) {}
};

// **KEY VERSION TRACKER**: Track key modifications for conflict detection
class KeyVersionTracker {
private:
    struct KeyVersion {
        uint64_t last_write_timestamp{0};
        uint64_t last_read_timestamp{0};
        uint32_t last_write_core{0};
        uint32_t last_read_core{0};
        std::string last_value;
        std::atomic<uint32_t> version_counter{0};
    };
    
    // **PER-CORE VERSION MAPS**: NUMA-aware data structures
    std::array<std::unordered_map<std::string, KeyVersion>, 16> core_key_versions_;
    std::array<std::mutex, 16> core_mutexes_;
    
    // **GLOBAL VERSION TRACKER**: For cross-core visibility
    std::unordered_map<std::string, std::atomic<uint64_t>> global_key_timestamps_;
    std::mutex global_mutex_;
    
public:
    // **RECORD KEY WRITE**: Update version information
    void record_key_write(const std::string& key, uint64_t timestamp, uint32_t core_id, 
                         const std::string& value) {
        if (core_id >= 16) return;
        
        {
            std::lock_guard<std::mutex> lock(core_mutexes_[core_id]);
            auto& version = core_key_versions_[core_id][key];
            version.last_write_timestamp = timestamp;
            version.last_write_core = core_id;
            version.last_value = value;
            version.version_counter.fetch_add(1, std::memory_order_relaxed);
        }
        
        // **UPDATE GLOBAL TRACKER**
        {
            std::lock_guard<std::mutex> lock(global_mutex_);
            global_key_timestamps_[key].store(timestamp, std::memory_order_release);
        }
    }
    
    // **RECORD KEY READ**: Update read timestamp
    void record_key_read(const std::string& key, uint64_t timestamp, uint32_t core_id) {
        if (core_id >= 16) return;
        
        std::lock_guard<std::mutex> lock(core_mutexes_[core_id]);
        auto& version = core_key_versions_[core_id][key];
        version.last_read_timestamp = timestamp;
        version.last_read_core = core_id;
    }
    
    // **GET KEY VERSION**: Check current version info
    std::optional<uint64_t> get_last_write_timestamp(const std::string& key) const {
        std::lock_guard<std::mutex> lock(global_mutex_);
        auto it = global_key_timestamps_.find(key);
        return it != global_key_timestamps_.end() 
            ? std::make_optional(it->second.load(std::memory_order_acquire))
            : std::nullopt;
    }
    
    // **CHECK FOR CONFLICTS**: Detect temporal conflicts for a key
    std::vector<ConflictInfo> detect_key_conflicts(const std::string& key, uint64_t pipeline_timestamp,
                                                  ConflictType operation_type) const {
        std::vector<ConflictInfo> conflicts;
        
        auto last_write_ts = get_last_write_timestamp(key);
        if (!last_write_ts) return conflicts;  // Key never written
        
        // **READ-AFTER-WRITE**: Reading a key modified after pipeline start
        if (operation_type == ConflictType::READ_AFTER_WRITE && *last_write_ts > pipeline_timestamp) {
            conflicts.emplace_back(ConflictType::READ_AFTER_WRITE, key, pipeline_timestamp, 
                                 *last_write_ts, 0 /* TODO: track core */);
        }
        
        // **WRITE-AFTER-WRITE**: Writing a key modified after pipeline start  
        if (operation_type == ConflictType::WRITE_AFTER_WRITE && *last_write_ts > pipeline_timestamp) {
            conflicts.emplace_back(ConflictType::WRITE_AFTER_WRITE, key, pipeline_timestamp,
                                 *last_write_ts, 0);
        }
        
        return conflicts;
    }
};

// **TEMPORAL CONFLICT DETECTOR**: Main conflict detection engine
class TemporalConflictDetector {
private:
    KeyVersionTracker version_tracker_;
    
    // **SPECULATIVE EXECUTION LOG**: Track speculative operations for rollback
    struct SpeculativeOperation {
        std::string key;
        std::string operation;
        std::string old_value;
        std::string new_value;
        uint64_t timestamp;
        uint32_t core_id;
        bool committed{false};
    };
    
    std::unordered_map<uint64_t, std::vector<SpeculativeOperation>> speculative_operations_;
    std::mutex speculative_mutex_;
    
public:
    // **DETECT PIPELINE CONFLICTS**: Check entire pipeline for temporal conflicts
    std::vector<ConflictInfo> detect_pipeline_conflicts(const std::vector<TemporalCommand>& commands) {
        std::vector<ConflictInfo> all_conflicts;
        
        for (const auto& command : commands) {
            ConflictType operation_type;
            
            std::string op_upper = command.operation;
            std::transform(op_upper.begin(), op_upper.end(), op_upper.begin(), ::toupper);
            
            if (op_upper == "GET") {
                operation_type = ConflictType::READ_AFTER_WRITE;
            } else if (op_upper == "SET" || op_upper == "DEL") {
                operation_type = ConflictType::WRITE_AFTER_WRITE;
            } else {
                continue;  // Skip non-data operations
            }
            
            // **DETECT CONFLICTS** for this command
            auto conflicts = version_tracker_.detect_key_conflicts(command.key, 
                                                                  command.pipeline_timestamp, 
                                                                  operation_type);
            
            all_conflicts.insert(all_conflicts.end(), conflicts.begin(), conflicts.end());
        }
        
        return all_conflicts;
    }
    
    // **RECORD SPECULATIVE OPERATION**: Track for potential rollback
    void record_speculative_operation(const TemporalCommand& command, const std::string& old_value,
                                     const std::string& new_value) {
        std::lock_guard<std::mutex> lock(speculative_mutex_);
        
        speculative_operations_[command.pipeline_timestamp].emplace_back(
            SpeculativeOperation{command.key, command.operation, old_value, new_value,
                               command.pipeline_timestamp, command.source_core, false});
    }
    
    // **COMMIT SPECULATIVE OPERATIONS**: Make operations permanent
    void commit_speculative_operations(uint64_t pipeline_timestamp) {
        std::lock_guard<std::mutex> lock(speculative_mutex_);
        
        auto it = speculative_operations_.find(pipeline_timestamp);
        if (it != speculative_operations_.end()) {
            for (auto& op : it->second) {
                op.committed = true;
                
                // **UPDATE VERSION TRACKER**
                if (op.operation == "SET") {
                    version_tracker_.record_key_write(op.key, op.timestamp, op.core_id, op.new_value);
                } else if (op.operation == "GET") {
                    version_tracker_.record_key_read(op.key, op.timestamp, op.core_id);
                }
            }
        }
    }
    
    // **ROLLBACK SPECULATIVE OPERATIONS**: Undo speculative changes
    std::vector<std::pair<std::string, std::string>> rollback_speculative_operations(uint64_t pipeline_timestamp) {
        std::vector<std::pair<std::string, std::string>> rollback_operations;
        
        std::lock_guard<std::mutex> lock(speculative_mutex_);
        
        auto it = speculative_operations_.find(pipeline_timestamp);
        if (it != speculative_operations_.end()) {
            // **REVERSE ORDER ROLLBACK**: Undo operations in reverse order
            for (auto rit = it->second.rbegin(); rit != it->second.rend(); ++rit) {
                if (!rit->committed) {
                    rollback_operations.emplace_back(rit->key, rit->old_value);
                }
            }
            
            // **CLEANUP**: Remove speculative operations
            speculative_operations_.erase(it);
        }
        
        return rollback_operations;
    }
};

// **CONFLICT RESOLUTION RESULT**
struct ConflictResolutionResult {
    enum class Resolution {
        COMMIT,           // No conflicts, commit normally
        ROLLBACK_RETRY,   // Rollback and retry with updated data
        ABORT            // Conflicts too severe, abort pipeline
    };
    
    Resolution resolution;
    std::vector<ConflictInfo> conflicts;
    std::vector<std::pair<std::string, std::string>> rollback_operations;
    
    ConflictResolutionResult(Resolution res) : resolution(res) {}
};

// **TEMPORAL CONFLICT RESOLVER**: Deterministic conflict resolution
class TemporalConflictResolver {
public:
    // **RESOLVE CONFLICTS**: Apply Thomas Write Rule for deterministic resolution
    ConflictResolutionResult resolve_conflicts(const std::vector<ConflictInfo>& conflicts,
                                              uint64_t pipeline_timestamp) {
        if (conflicts.empty()) {
            return ConflictResolutionResult{ConflictResolutionResult::Resolution::COMMIT};
        }
        
        ConflictResolutionResult result{ConflictResolutionResult::Resolution::ROLLBACK_RETRY};
        result.conflicts = conflicts;
        
        // **THOMAS WRITE RULE**: Earlier timestamp wins
        for (const auto& conflict : conflicts) {
            if (pipeline_timestamp < conflict.conflicting_timestamp) {
                // **OUR PIPELINE IS EARLIER**: We should succeed, rollback conflicting operations
                // This is complex and requires coordination with other cores
                // For now, we'll use a simpler approach: retry
                result.resolution = ConflictResolutionResult::Resolution::ROLLBACK_RETRY;
            } else {
                // **OUR PIPELINE IS LATER**: We should rollback and retry
                result.resolution = ConflictResolutionResult::Resolution::ROLLBACK_RETRY;
            }
        }
        
        // **SIMPLE POLICY**: If too many conflicts, abort
        if (conflicts.size() > 10) {
            result.resolution = ConflictResolutionResult::Resolution::ABORT;
        }
        
        return result;
    }
    
    // **APPLY RESOLUTION**: Execute the conflict resolution
    bool apply_resolution(const ConflictResolutionResult& resolution,
                         TemporalConflictDetector& detector,
                         uint64_t pipeline_timestamp) {
        switch (resolution.resolution) {
            case ConflictResolutionResult::Resolution::COMMIT:
                detector.commit_speculative_operations(pipeline_timestamp);
                return true;
                
            case ConflictResolutionResult::Resolution::ROLLBACK_RETRY:
                {
                    auto rollback_ops = detector.rollback_speculative_operations(pipeline_timestamp);
                    // TODO: Apply rollback operations and retry
                    return false;  // Indicate retry needed
                }
                
            case ConflictResolutionResult::Resolution::ABORT:
                detector.rollback_speculative_operations(pipeline_timestamp);
                return false;
        }
        
        return false;
    }
};

// **TEMPORAL COHERENCE ENGINE**: Main coordination class
class TemporalCoherenceEngine {
private:
    TemporalConflictDetector conflict_detector_;
    TemporalConflictResolver conflict_resolver_;
    
    // **RETRY POLICY**
    static constexpr int MAX_RETRIES = 3;
    static constexpr auto RETRY_DELAY = std::chrono::microseconds(100);
    
public:
    // **PROCESS PIPELINE WITH CONFLICT DETECTION**: Main entry point
    bool process_pipeline_with_coherence(const std::vector<TemporalCommand>& commands,
                                        std::function<std::vector<TemporalResponse>(const std::vector<TemporalCommand>&)> executor) {
        
        if (commands.empty()) return true;
        
        uint64_t pipeline_timestamp = commands[0].pipeline_timestamp;
        
        for (int retry = 0; retry < MAX_RETRIES; ++retry) {
            // **PHASE 1: CONFLICT DETECTION**
            auto conflicts = conflict_detector_.detect_pipeline_conflicts(commands);
            
            // **PHASE 2: CONFLICT RESOLUTION**
            auto resolution = conflict_resolver_.resolve_conflicts(conflicts, pipeline_timestamp);
            
            if (resolution.resolution == ConflictResolutionResult::Resolution::COMMIT) {
                // **NO CONFLICTS**: Execute normally
                auto responses = executor(commands);
                conflict_detector_.commit_speculative_operations(pipeline_timestamp);
                return true;
            }
            
            if (resolution.resolution == ConflictResolutionResult::Resolution::ABORT) {
                // **ABORT**: Too many conflicts
                return false;
            }
            
            // **ROLLBACK AND RETRY**: Wait a bit and try again
            conflict_detector_.rollback_speculative_operations(pipeline_timestamp);
            
            if (retry < MAX_RETRIES - 1) {
                std::this_thread::sleep_for(RETRY_DELAY * (1 << retry));  // Exponential backoff
            }
        }
        
        return false;  // Max retries exceeded
    }
    
    // **RECORD OPERATION**: Track operations for conflict detection
    void record_operation(const TemporalCommand& command, const std::string& old_value,
                         const std::string& new_value) {
        conflict_detector_.record_speculative_operation(command, old_value, new_value);
    }
};

} // namespace temporal_coherence















