#pragma once

#include <string>
#include <vector>
#include <memory>
#include <span>
#include <variant>
#include <optional>
#include <cstdint>

namespace meteor {
namespace protocol {

// RESP data types
enum class RESPType : uint8_t {
    SimpleString = '+',
    Error = '-',
    Integer = ':',
    BulkString = '$',
    Array = '*',
    Null = '_',
    Boolean = '#',
    Double = ',',
    BigNumber = '(',
    BulkError = '!',
    VerbatimString = '=',
    Map = '%',
    Attribute = '|',
    Set = '~',
    Push = '>'
};

// RESP value representation with zero-copy optimization
class RESPValue {
public:
    using ValueType = std::variant<
        std::monostate,           // Null
        std::string,              // SimpleString, Error, BulkString
        int64_t,                  // Integer
        double,                   // Double
        bool,                     // Boolean
        std::vector<RESPValue>    // Array, Map, Set
    >;
    
    RESPType type = RESPType::Null;
    ValueType value;
    
    // Constructors
    RESPValue() = default;
    explicit RESPValue(RESPType t) : type(t) {}
    RESPValue(RESPType t, std::string v) : type(t), value(std::move(v)) {}
    RESPValue(RESPType t, int64_t v) : type(t), value(v) {}
    RESPValue(RESPType t, double v) : type(t), value(v) {}
    RESPValue(RESPType t, bool v) : type(t), value(v) {}
    RESPValue(RESPType t, std::vector<RESPValue> v) : type(t), value(std::move(v)) {}
    
    // Type checking
    bool is_null() const { return type == RESPType::Null; }
    bool is_string() const { 
        return type == RESPType::SimpleString || 
               type == RESPType::BulkString || 
               type == RESPType::Error; 
    }
    bool is_integer() const { return type == RESPType::Integer; }
    bool is_array() const { return type == RESPType::Array; }
    bool is_error() const { return type == RESPType::Error; }
    
    // Value accessors
    const std::string& as_string() const { return std::get<std::string>(value); }
    int64_t as_integer() const { return std::get<int64_t>(value); }
    double as_double() const { return std::get<double>(value); }
    bool as_boolean() const { return std::get<bool>(value); }
    const std::vector<RESPValue>& as_array() const { return std::get<std::vector<RESPValue>>(value); }
    
    // Mutable accessors
    std::string& as_string() { return std::get<std::string>(value); }
    std::vector<RESPValue>& as_array() { return std::get<std::vector<RESPValue>>(value); }
    
    // Utility methods
    size_t size() const;
    std::string to_string() const;
    void clear();
};

// High-performance RESP parser with zero-copy optimization
class RESPParser {
public:
    explicit RESPParser(size_t buffer_size = 64 * 1024);
    ~RESPParser();
    
    // Non-copyable, movable
    RESPParser(const RESPParser&) = delete;
    RESPParser& operator=(const RESPParser&) = delete;
    RESPParser(RESPParser&&) = default;
    RESPParser& operator=(RESPParser&&) = default;
    
    // Parse methods
    std::optional<RESPValue> parse(std::span<const char> data);
    std::optional<RESPValue> parse_incremental(std::span<const char> data);
    
    // Buffer management
    void reset();
    size_t bytes_consumed() const { return bytes_consumed_; }
    bool needs_more_data() const { return needs_more_data_; }
    
    // Performance metrics
    struct ParseStats {
        uint64_t total_parses = 0;
        uint64_t parse_errors = 0;
        uint64_t bytes_parsed = 0;
        double avg_parse_time_ns = 0.0;
    };
    
    ParseStats get_stats() const { return stats_; }
    void reset_stats() { stats_ = {}; }

private:
    // Internal parsing state
    enum class ParseState {
        ReadType,
        ReadSimpleString,
        ReadError,
        ReadInteger,
        ReadBulkStringLength,
        ReadBulkStringData,
        ReadArrayLength,
        ReadArrayElements,
        Complete,
        Error
    };
    
    // Parser state
    std::vector<char> buffer_;
    size_t buffer_pos_ = 0;
    size_t buffer_size_ = 0;
    size_t bytes_consumed_ = 0;
    bool needs_more_data_ = false;
    
    // Parsing context
    ParseState state_ = ParseState::ReadType;
    std::vector<ParseState> state_stack_;
    std::vector<RESPValue> value_stack_;
    std::vector<size_t> length_stack_;
    
    // Statistics
    mutable ParseStats stats_;
    
    // Internal parsing methods
    std::optional<RESPValue> parse_internal();
    bool parse_simple_string(RESPValue& value);
    bool parse_error(RESPValue& value);
    bool parse_integer(RESPValue& value);
    bool parse_bulk_string(RESPValue& value);
    bool parse_array(RESPValue& value);
    
    // Utility methods
    std::optional<std::string> read_line();
    std::optional<int64_t> parse_integer_from_line(const std::string& line);
    bool has_complete_line() const;
    size_t find_crlf(size_t start = 0) const;
    
    // Buffer management
    void ensure_buffer_space(size_t needed);
    void compact_buffer();
    
    // Constants
    static constexpr size_t MAX_BULK_STRING_LENGTH = 512 * 1024 * 1024; // 512MB
    static constexpr size_t MAX_ARRAY_LENGTH = 1024 * 1024; // 1M elements
    static constexpr char CRLF[] = "\r\n";
};

// RESP serializer for responses
class RESPSerializer {
public:
    explicit RESPSerializer(size_t buffer_size = 64 * 1024);
    ~RESPSerializer() = default;
    
    // Non-copyable, movable
    RESPSerializer(const RESPSerializer&) = delete;
    RESPSerializer& operator=(const RESPSerializer&) = delete;
    RESPSerializer(RESPSerializer&&) = default;
    RESPSerializer& operator=(RESPSerializer&&) = default;
    
    // Serialization methods
    void serialize(const RESPValue& value);
    void serialize_simple_string(const std::string& str);
    void serialize_error(const std::string& error);
    void serialize_integer(int64_t value);
    void serialize_bulk_string(const std::string& str);
    void serialize_null_bulk_string();
    void serialize_array(const std::vector<RESPValue>& array);
    void serialize_null_array();
    
    // Buffer access
    std::span<const char> data() const;
    size_t size() const { return buffer_pos_; }
    void clear();
    
    // Utility methods
    std::string to_string() const;

private:
    std::vector<char> buffer_;
    size_t buffer_pos_ = 0;
    
    // Internal methods
    void ensure_capacity(size_t needed);
    void append(const char* data, size_t length);
    void append(char c);
    void append_crlf();
    void append_integer(int64_t value);
    
    // Constants
    static constexpr size_t INITIAL_BUFFER_SIZE = 64 * 1024;
    static constexpr size_t MAX_BUFFER_SIZE = 64 * 1024 * 1024; // 64MB
};

// Command parser for Redis commands
class CommandParser {
public:
    struct Command {
        std::string name;
        std::vector<std::string> args;
        
        Command() = default;
        Command(std::string n, std::vector<std::string> a) 
            : name(std::move(n)), args(std::move(a)) {}
    };
    
    static std::optional<Command> parse_command(const RESPValue& value);
    static bool is_valid_command(const RESPValue& value);
    
private:
    static std::string normalize_command_name(const std::string& name);
};

} // namespace protocol
} // namespace meteor 