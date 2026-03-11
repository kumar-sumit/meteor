#pragma once

#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace meteor {
namespace utils {
class MemoryPool;
class BufferPool;
}

namespace protocol {

enum class RESPType {
    SIMPLE_STRING,
    ERROR,
    INTEGER,
    BULK_STRING,
    ARRAY,
    NIL
};

struct RESPValue {
    RESPType type;
    std::string string_value;
    int64_t integer_value = 0;
    std::vector<RESPValue> array_value;
    
    RESPValue() = default;
    RESPValue(const RESPValue&) = default;
    RESPValue(RESPValue&&) = default;
    RESPValue& operator=(const RESPValue&) = default;
    RESPValue& operator=(RESPValue&&) = default;
};

enum class ParseStatus {
    NEED_MORE_DATA,
    COMPLETE,
    ERROR
};

struct ParseResult {
    ParseStatus status;
    RESPValue value;
    size_t bytes_consumed;
};

enum class ParseState {
    WAITING_FOR_COMMAND,
    READING_ARRAY_SIZE,
    READING_BULK_SIZE,
    READING_BULK_DATA,
    READING_SIMPLE_STRING,
    READING_INTEGER,
    READING_ERROR
};

class RESPParser {
public:
    explicit RESPParser(utils::MemoryPool& memory_pool);
    ~RESPParser();

    // Disable copy and move
    RESPParser(const RESPParser&) = delete;
    RESPParser& operator=(const RESPParser&) = delete;
    RESPParser(RESPParser&&) = delete;
    RESPParser& operator=(RESPParser&&) = delete;

    // Parse RESP data with zero-copy optimization
    ParseResult parse(std::string_view data);
    
    // Reset parser state
    void reset();

private:
    utils::MemoryPool& memory_pool_;
    std::unique_ptr<utils::BufferPool> buffer_pool_;
    
    // Parser state
    ParseState parse_state_;
    std::string input_buffer_;
    size_t bytes_parsed_;
    
    // Array parsing state
    int current_array_size_;
    int current_array_index_;
    std::vector<RESPValue> current_array_;
    
    // Bulk string parsing state
    int current_bulk_size_;
    
    // Private parsing methods
    ParseResult parse_next_token();
    ParseResult parse_command_start();
    ParseResult parse_array_size();
    ParseResult parse_array_element();
    ParseResult parse_bulk_size();
    ParseResult parse_bulk_data();
    ParseResult parse_simple_string();
    ParseResult parse_integer();
    ParseResult parse_error();
    
    // Utility methods
    size_t find_crlf() const;
    void consume_bytes(size_t count);
    void reset_parser_state();
};

class RESPSerializer {
public:
    explicit RESPSerializer(utils::MemoryPool& memory_pool);
    ~RESPSerializer();

    // Disable copy and move
    RESPSerializer(const RESPSerializer&) = delete;
    RESPSerializer& operator=(const RESPSerializer&) = delete;
    RESPSerializer(RESPSerializer&&) = delete;
    RESPSerializer& operator=(RESPSerializer&&) = delete;

    // Serialize RESP value to string
    std::string serialize(const RESPValue& value);

private:
    utils::MemoryPool& memory_pool_;
    std::unique_ptr<utils::BufferPool> buffer_pool_;
    
    // Serialization methods
    std::string serialize_simple_string(const std::string& str);
    std::string serialize_error(const std::string& str);
    std::string serialize_integer(int64_t value);
    std::string serialize_bulk_string(const std::string& str);
    std::string serialize_array(const std::vector<RESPValue>& array);
    std::string serialize_nil();
};

// Utility functions for creating RESP values
RESPValue create_simple_string(const std::string& str);
RESPValue create_error(const std::string& str);
RESPValue create_integer(int64_t num);
RESPValue create_bulk_string(const std::string& str);
RESPValue create_array(const std::vector<RESPValue>& array);
RESPValue create_nil();

} // namespace protocol
} // namespace meteor 