#include "resp_parser.hpp"
#include <charconv>
#include <algorithm>
#include <sstream>

namespace garuda::protocol {

RespParser::RespParser() = default;

ParseResult RespParser::Parse(std::span<const char> data) {
    needs_more_data_ = false;
    
    if (data.empty()) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, 0, "Empty data"};
    }
    
    size_t pos = 0;
    return ParseValue(data, pos);
}

void RespParser::Reset() {
    needs_more_data_ = false;
    partial_data_.clear();
}

ParseResult RespParser::ParseValue(std::span<const char> data, size_t& pos) {
    if (pos >= data.size()) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, pos, "Need more data for type byte"};
    }
    
    char type_byte = data[pos++];
    RespType type = static_cast<RespType>(type_byte);
    
    switch (type) {
        case RespType::SIMPLE_STRING:
            return ParseSimpleString(data, pos);
        case RespType::ERROR:
            return ParseError(data, pos);
        case RespType::INTEGER:
            return ParseInteger(data, pos);
        case RespType::BULK_STRING:
            return ParseBulkString(data, pos);
        case RespType::ARRAY:
            return ParseArray(data, pos);
        default:
            return {ParseStatus::ERROR, {}, pos, "Unknown RESP type: " + std::string(1, type_byte)};
    }
}

ParseResult RespParser::ParseSimpleString(std::span<const char> data, size_t& pos) {
    auto crlf_pos = FindCRLF(data, pos);
    if (!crlf_pos) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, pos, "Need more data for simple string"};
    }
    
    std::string str(data.data() + pos, *crlf_pos - pos);
    pos = *crlf_pos + 2; // Skip CRLF
    
    return {ParseStatus::OK, RespValue::CreateSimpleString(str), pos, ""};
}

ParseResult RespParser::ParseError(std::span<const char> data, size_t& pos) {
    auto crlf_pos = FindCRLF(data, pos);
    if (!crlf_pos) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, pos, "Need more data for error"};
    }
    
    std::string error_msg(data.data() + pos, *crlf_pos - pos);
    pos = *crlf_pos + 2; // Skip CRLF
    
    return {ParseStatus::OK, RespValue::CreateError(error_msg), pos, ""};
}

ParseResult RespParser::ParseInteger(std::span<const char> data, size_t& pos) {
    auto crlf_pos = FindCRLF(data, pos);
    if (!crlf_pos) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, pos, "Need more data for integer"};
    }
    
    auto int_val = ParseIntegerFromLine(data, pos, *crlf_pos);
    if (!int_val) {
        return {ParseStatus::ERROR, {}, pos, "Invalid integer format"};
    }
    
    pos = *crlf_pos + 2; // Skip CRLF
    return {ParseStatus::OK, RespValue(*int_val), pos, ""};
}

ParseResult RespParser::ParseBulkString(std::span<const char> data, size_t& pos) {
    auto crlf_pos = FindCRLF(data, pos);
    if (!crlf_pos) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, pos, "Need more data for bulk string length"};
    }
    
    auto length = ParseIntegerFromLine(data, pos, *crlf_pos);
    if (!length) {
        return {ParseStatus::ERROR, {}, pos, "Invalid bulk string length"};
    }
    
    pos = *crlf_pos + 2; // Skip CRLF
    
    if (*length == -1) {
        return {ParseStatus::OK, RespValue::CreateNull(), pos, ""};
    }
    
    if (*length < 0) {
        return {ParseStatus::ERROR, {}, pos, "Invalid bulk string length: " + std::to_string(*length)};
    }
    
    size_t str_length = static_cast<size_t>(*length);
    if (pos + str_length + 2 > data.size()) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, pos, "Need more data for bulk string content"};
    }
    
    std::string str(data.data() + pos, str_length);
    pos += str_length + 2; // Skip string and CRLF
    
    return {ParseStatus::OK, RespValue(str), pos, ""};
}

ParseResult RespParser::ParseArray(std::span<const char> data, size_t& pos) {
    auto crlf_pos = FindCRLF(data, pos);
    if (!crlf_pos) {
        needs_more_data_ = true;
        return {ParseStatus::NEED_MORE_DATA, {}, pos, "Need more data for array length"};
    }
    
    auto length = ParseIntegerFromLine(data, pos, *crlf_pos);
    if (!length) {
        return {ParseStatus::ERROR, {}, pos, "Invalid array length"};
    }
    
    pos = *crlf_pos + 2; // Skip CRLF
    
    if (*length == -1) {
        return {ParseStatus::OK, RespValue::CreateNull(), pos, ""};
    }
    
    if (*length < 0) {
        return {ParseStatus::ERROR, {}, pos, "Invalid array length: " + std::to_string(*length)};
    }
    
    std::vector<RespValue> array;
    array.reserve(static_cast<size_t>(*length));
    
    for (int64_t i = 0; i < *length; ++i) {
        auto element_result = ParseValue(data, pos);
        if (element_result.status != ParseStatus::OK) {
            return element_result;
        }
        array.push_back(std::move(element_result.value));
    }
    
    return {ParseStatus::OK, RespValue::CreateArray(std::move(array)), pos, ""};
}

std::optional<size_t> RespParser::FindCRLF(std::span<const char> data, size_t start_pos) {
    for (size_t i = start_pos; i < data.size() - 1; ++i) {
        if (data[i] == '\r' && data[i + 1] == '\n') {
            return i;
        }
    }
    return std::nullopt;
}

std::optional<int64_t> RespParser::ParseIntegerFromLine(std::span<const char> data, size_t start, size_t end) {
    if (start >= end) {
        return std::nullopt;
    }
    
    std::string_view str_view(data.data() + start, end - start);
    int64_t result;
    auto [ptr, ec] = std::from_chars(str_view.data(), str_view.data() + str_view.size(), result);
    
    if (ec == std::errc{} && ptr == str_view.data() + str_view.size()) {
        return result;
    }
    
    return std::nullopt;
}

// RespSerializer implementation
std::string RespSerializer::Serialize(const RespValue& value) {
    switch (value.type) {
        case RespType::SIMPLE_STRING:
            return SerializeSimpleString(value.str_val);
        case RespType::ERROR:
            return SerializeError(value.str_val);
        case RespType::INTEGER:
            return SerializeInteger(value.int_val);
        case RespType::BULK_STRING:
            if (value.is_null) {
                return SerializeNull();
            }
            return SerializeBulkString(value.str_val);
        case RespType::ARRAY:
            return SerializeArray(value.array_val);
        case RespType::NULL_TYPE:
            return SerializeNull();
        default:
            return SerializeError("Unsupported type");
    }
}

std::string RespSerializer::SerializeSimpleString(const std::string& str) {
    return "+" + str + "\r\n";
}

std::string RespSerializer::SerializeError(const std::string& error) {
    return "-" + error + "\r\n";
}

std::string RespSerializer::SerializeInteger(int64_t value) {
    return ":" + std::to_string(value) + "\r\n";
}

std::string RespSerializer::SerializeBulkString(const std::string& str) {
    return "$" + std::to_string(str.length()) + "\r\n" + str + "\r\n";
}

std::string RespSerializer::SerializeArray(const std::vector<RespValue>& arr) {
    std::string result = "*" + std::to_string(arr.size()) + "\r\n";
    for (const auto& item : arr) {
        result += Serialize(item);
    }
    return result;
}

std::string RespSerializer::SerializeNull() {
    return "$-1\r\n";
}

} // namespace garuda::protocol