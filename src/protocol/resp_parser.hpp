#pragma once

#include <string>
#include <vector>
#include <span>
#include <optional>
#include <cstdint>

namespace garuda::protocol {

enum class RespType : uint8_t {
    SIMPLE_STRING = '+',
    ERROR = '-',
    INTEGER = ':',
    BULK_STRING = '$',
    ARRAY = '*',
    NULL_TYPE = '_',
    BOOLEAN = '#',
    DOUBLE = ',',
    BIG_NUMBER = '(',
    BULK_ERROR = '!',
    VERBATIM_STRING = '=',
    MAP = '%',
    SET = '~',
    PUSH = '>'
};

struct RespValue {
    RespType type;
    std::string str_val;
    int64_t int_val = 0;
    double double_val = 0.0;
    bool bool_val = false;
    std::vector<RespValue> array_val;
    bool is_null = false;

    RespValue() = default;
    explicit RespValue(RespType t) : type(t) {}
    explicit RespValue(const std::string& s) : type(RespType::BULK_STRING), str_val(s) {}
    explicit RespValue(int64_t i) : type(RespType::INTEGER), int_val(i) {}
    explicit RespValue(double d) : type(RespType::DOUBLE), double_val(d) {}
    explicit RespValue(bool b) : type(RespType::BOOLEAN), bool_val(b) {}
    
    static RespValue CreateNull() {
        RespValue val(RespType::NULL_TYPE);
        val.is_null = true;
        return val;
    }
    
    static RespValue CreateError(const std::string& msg) {
        RespValue val(RespType::ERROR);
        val.str_val = msg;
        return val;
    }
    
    static RespValue CreateSimpleString(const std::string& s) {
        RespValue val(RespType::SIMPLE_STRING);
        val.str_val = s;
        return val;
    }
    
    static RespValue CreateArray(std::vector<RespValue> arr) {
        RespValue val(RespType::ARRAY);
        val.array_val = std::move(arr);
        return val;
    }
};

enum class ParseStatus {
    OK,
    NEED_MORE_DATA,
    ERROR
};

struct ParseResult {
    ParseStatus status;
    RespValue value;
    size_t consumed_bytes = 0;
    std::string error_msg;
};

class RespParser {
public:
    RespParser();
    ~RespParser() = default;

    // Parse RESP data from buffer
    ParseResult Parse(std::span<const char> data);
    
    // Reset parser state
    void Reset();
    
    // Check if parser needs more data
    bool NeedsMoreData() const { return needs_more_data_; }
    
private:
    ParseResult ParseValue(std::span<const char> data, size_t& pos);
    ParseResult ParseSimpleString(std::span<const char> data, size_t& pos);
    ParseResult ParseError(std::span<const char> data, size_t& pos);
    ParseResult ParseInteger(std::span<const char> data, size_t& pos);
    ParseResult ParseBulkString(std::span<const char> data, size_t& pos);
    ParseResult ParseArray(std::span<const char> data, size_t& pos);
    
    std::optional<size_t> FindCRLF(std::span<const char> data, size_t start_pos);
    std::optional<int64_t> ParseIntegerFromLine(std::span<const char> data, size_t start, size_t end);
    
    bool needs_more_data_ = false;
    std::string partial_data_;
};

// RESP serializer for responses
class RespSerializer {
public:
    static std::string Serialize(const RespValue& value);
    static std::string SerializeSimpleString(const std::string& str);
    static std::string SerializeError(const std::string& error);
    static std::string SerializeInteger(int64_t value);
    static std::string SerializeBulkString(const std::string& str);
    static std::string SerializeArray(const std::vector<RespValue>& arr);
    static std::string SerializeNull();
};

} // namespace garuda::protocol