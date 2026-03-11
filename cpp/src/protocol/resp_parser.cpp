#include "../../include/protocol/resp_parser.hpp"
#include <algorithm>
#include <charconv>
#include <cstring>
#include <chrono>

namespace meteor {
namespace protocol {

// RESPValue implementation
size_t RESPValue::size() const {
    switch (type) {
        case RESPType::Null:
            return 0;
        case RESPType::SimpleString:
        case RESPType::Error:
        case RESPType::BulkString:
            return std::get<std::string>(value).size();
        case RESPType::Integer:
            return sizeof(int64_t);
        case RESPType::Double:
            return sizeof(double);
        case RESPType::Boolean:
            return sizeof(bool);
        case RESPType::Array:
        case RESPType::Map:
        case RESPType::Set: {
            size_t total = 0;
            for (const auto& item : std::get<std::vector<RESPValue>>(value)) {
                total += item.size();
            }
            return total;
        }
        default:
            return 0;
    }
}

std::string RESPValue::to_string() const {
    switch (type) {
        case RESPType::Null:
            return "(null)";
        case RESPType::SimpleString:
        case RESPType::Error:
        case RESPType::BulkString:
            return std::get<std::string>(value);
        case RESPType::Integer:
            return std::to_string(std::get<int64_t>(value));
        case RESPType::Double:
            return std::to_string(std::get<double>(value));
        case RESPType::Boolean:
            return std::get<bool>(value) ? "true" : "false";
        case RESPType::Array:
        case RESPType::Map:
        case RESPType::Set: {
            std::string result = "[";
            const auto& arr = std::get<std::vector<RESPValue>>(value);
            for (size_t i = 0; i < arr.size(); ++i) {
                if (i > 0) result += ", ";
                result += arr[i].to_string();
            }
            result += "]";
            return result;
        }
        default:
            return "(unknown)";
    }
}

void RESPValue::clear() {
    type = RESPType::Null;
    value = std::monostate{};
}

// RESPParser implementation
RESPParser::RESPParser(size_t buffer_size) : buffer_(buffer_size) {
    buffer_.reserve(buffer_size);
}

RESPParser::~RESPParser() = default;

std::optional<RESPValue> RESPParser::parse(std::span<const char> data) {
    // Reset parser state
    reset();
    
    // Copy data to internal buffer
    ensure_buffer_space(data.size());
    std::memcpy(buffer_.data() + buffer_size_, data.data(), data.size());
    buffer_size_ += data.size();
    
    return parse_internal();
}

std::optional<RESPValue> RESPParser::parse_incremental(std::span<const char> data) {
    auto start_time = std::chrono::high_resolution_clock::now();
    
    // Append new data to buffer
    ensure_buffer_space(data.size());
    std::memcpy(buffer_.data() + buffer_size_, data.data(), data.size());
    buffer_size_ += data.size();
    
    auto result = parse_internal();
    
    // Update statistics
    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - start_time);
    
    stats_.total_parses++;
    stats_.bytes_parsed += data.size();
    stats_.avg_parse_time_ns = (stats_.avg_parse_time_ns * (stats_.total_parses - 1) + 
                               duration.count()) / stats_.total_parses;
    
    if (!result) {
        stats_.parse_errors++;
    }
    
    return result;
}

void RESPParser::reset() {
    buffer_pos_ = 0;
    buffer_size_ = 0;
    bytes_consumed_ = 0;
    needs_more_data_ = false;
    state_ = ParseState::ReadType;
    state_stack_.clear();
    value_stack_.clear();
    length_stack_.clear();
}

std::optional<RESPValue> RESPParser::parse_internal() {
    while (buffer_pos_ < buffer_size_) {
        switch (state_) {
            case ParseState::ReadType: {
                if (buffer_pos_ >= buffer_size_) {
                    needs_more_data_ = true;
                    return std::nullopt;
                }
                
                char type_char = buffer_[buffer_pos_++];
                bytes_consumed_++;
                
                RESPValue value;
                value.type = static_cast<RESPType>(type_char);
                
                switch (value.type) {
                    case RESPType::SimpleString:
                        state_ = ParseState::ReadSimpleString;
                        value_stack_.push_back(std::move(value));
                        break;
                    case RESPType::Error:
                        state_ = ParseState::ReadError;
                        value_stack_.push_back(std::move(value));
                        break;
                    case RESPType::Integer:
                        state_ = ParseState::ReadInteger;
                        value_stack_.push_back(std::move(value));
                        break;
                    case RESPType::BulkString:
                        state_ = ParseState::ReadBulkStringLength;
                        value_stack_.push_back(std::move(value));
                        break;
                    case RESPType::Array:
                        state_ = ParseState::ReadArrayLength;
                        value_stack_.push_back(std::move(value));
                        break;
                    default:
                        // Unsupported type
                        state_ = ParseState::Error;
                        return std::nullopt;
                }
                break;
            }
            
            case ParseState::ReadSimpleString: {
                if (!parse_simple_string(value_stack_.back())) {
                    return std::nullopt;
                }
                state_ = ParseState::Complete;
                break;
            }
            
            case ParseState::ReadError: {
                if (!parse_error(value_stack_.back())) {
                    return std::nullopt;
                }
                state_ = ParseState::Complete;
                break;
            }
            
            case ParseState::ReadInteger: {
                if (!parse_integer(value_stack_.back())) {
                    return std::nullopt;
                }
                state_ = ParseState::Complete;
                break;
            }
            
            case ParseState::ReadBulkStringLength: {
                auto line = read_line();
                if (!line) {
                    needs_more_data_ = true;
                    return std::nullopt;
                }
                
                auto length = parse_integer_from_line(*line);
                if (!length) {
                    state_ = ParseState::Error;
                    return std::nullopt;
                }
                
                if (*length == -1) {
                    // Null bulk string
                    value_stack_.back().type = RESPType::Null;
                    state_ = ParseState::Complete;
                } else if (*length < 0 || *length > MAX_BULK_STRING_LENGTH) {
                    state_ = ParseState::Error;
                    return std::nullopt;
                } else {
                    length_stack_.push_back(*length);
                    state_ = ParseState::ReadBulkStringData;
                }
                break;
            }
            
            case ParseState::ReadBulkStringData: {
                if (!parse_bulk_string(value_stack_.back())) {
                    return std::nullopt;
                }
                length_stack_.pop_back();
                state_ = ParseState::Complete;
                break;
            }
            
            case ParseState::ReadArrayLength: {
                auto line = read_line();
                if (!line) {
                    needs_more_data_ = true;
                    return std::nullopt;
                }
                
                auto length = parse_integer_from_line(*line);
                if (!length) {
                    state_ = ParseState::Error;
                    return std::nullopt;
                }
                
                if (*length == -1) {
                    // Null array
                    value_stack_.back().type = RESPType::Null;
                    state_ = ParseState::Complete;
                } else if (*length < 0 || *length > MAX_ARRAY_LENGTH) {
                    state_ = ParseState::Error;
                    return std::nullopt;
                } else {
                    length_stack_.push_back(*length);
                    value_stack_.back().value = std::vector<RESPValue>();
                    state_ = ParseState::ReadArrayElements;
                }
                break;
            }
            
            case ParseState::ReadArrayElements: {
                if (!parse_array(value_stack_.back())) {
                    return std::nullopt;
                }
                length_stack_.pop_back();
                state_ = ParseState::Complete;
                break;
            }
            
            case ParseState::Complete: {
                if (value_stack_.empty()) {
                    state_ = ParseState::Error;
                    return std::nullopt;
                }
                
                auto result = std::move(value_stack_.back());
                value_stack_.pop_back();
                
                // Compact buffer if needed
                compact_buffer();
                
                return result;
            }
            
            case ParseState::Error:
            default:
                return std::nullopt;
        }
    }
    
    needs_more_data_ = true;
    return std::nullopt;
}

bool RESPParser::parse_simple_string(RESPValue& value) {
    auto line = read_line();
    if (!line) {
        needs_more_data_ = true;
        return false;
    }
    
    value.value = std::move(*line);
    return true;
}

bool RESPParser::parse_error(RESPValue& value) {
    auto line = read_line();
    if (!line) {
        needs_more_data_ = true;
        return false;
    }
    
    value.value = std::move(*line);
    return true;
}

bool RESPParser::parse_integer(RESPValue& value) {
    auto line = read_line();
    if (!line) {
        needs_more_data_ = true;
        return false;
    }
    
    auto integer_value = parse_integer_from_line(*line);
    if (!integer_value) {
        return false;
    }
    
    value.value = *integer_value;
    return true;
}

bool RESPParser::parse_bulk_string(RESPValue& value) {
    if (length_stack_.empty()) {
        return false;
    }
    
    size_t length = length_stack_.back();
    
    // Check if we have enough data (length + CRLF)
    if (buffer_pos_ + length + 2 > buffer_size_) {
        needs_more_data_ = true;
        return false;
    }
    
    // Extract string data
    std::string str_data(buffer_.data() + buffer_pos_, length);
    buffer_pos_ += length;
    bytes_consumed_ += length;
    
    // Skip CRLF
    if (buffer_pos_ + 2 > buffer_size_ || 
        buffer_[buffer_pos_] != '\r' || 
        buffer_[buffer_pos_ + 1] != '\n') {
        return false;
    }
    
    buffer_pos_ += 2;
    bytes_consumed_ += 2;
    
    value.value = std::move(str_data);
    return true;
}

bool RESPParser::parse_array(RESPValue& value) {
    if (length_stack_.empty()) {
        return false;
    }
    
    size_t array_length = length_stack_.back();
    auto& array = std::get<std::vector<RESPValue>>(value.value);
    
    while (array.size() < array_length) {
        // Save current state
        auto saved_state = state_;
        auto saved_pos = buffer_pos_;
        auto saved_consumed = bytes_consumed_;
        
        // Try to parse next element
        state_ = ParseState::ReadType;
        auto element = parse_internal();
        
        if (!element) {
            // Restore state and wait for more data
            state_ = saved_state;
            buffer_pos_ = saved_pos;
            bytes_consumed_ = saved_consumed;
            needs_more_data_ = true;
            return false;
        }
        
        array.push_back(std::move(*element));
    }
    
    return true;
}

std::optional<std::string> RESPParser::read_line() {
    if (!has_complete_line()) {
        return std::nullopt;
    }
    
    size_t crlf_pos = find_crlf(buffer_pos_);
    if (crlf_pos == std::string::npos) {
        return std::nullopt;
    }
    
    std::string line(buffer_.data() + buffer_pos_, crlf_pos - buffer_pos_);
    buffer_pos_ = crlf_pos + 2; // Skip CRLF
    bytes_consumed_ += line.size() + 2;
    
    return line;
}

std::optional<int64_t> RESPParser::parse_integer_from_line(const std::string& line) {
    if (line.empty()) {
        return std::nullopt;
    }
    
    int64_t result;
    auto [ptr, ec] = std::from_chars(line.data(), line.data() + line.size(), result);
    
    if (ec == std::errc{} && ptr == line.data() + line.size()) {
        return result;
    }
    
    return std::nullopt;
}

bool RESPParser::has_complete_line() const {
    return find_crlf(buffer_pos_) != std::string::npos;
}

size_t RESPParser::find_crlf(size_t start) const {
    for (size_t i = start; i < buffer_size_ - 1; ++i) {
        if (buffer_[i] == '\r' && buffer_[i + 1] == '\n') {
            return i;
        }
    }
    return std::string::npos;
}

void RESPParser::ensure_buffer_space(size_t needed) {
    if (buffer_size_ + needed > buffer_.size()) {
        buffer_.resize(std::max(buffer_.size() * 2, buffer_size_ + needed));
    }
}

void RESPParser::compact_buffer() {
    if (buffer_pos_ > 0 && buffer_pos_ < buffer_size_) {
        std::memmove(buffer_.data(), buffer_.data() + buffer_pos_, buffer_size_ - buffer_pos_);
        buffer_size_ -= buffer_pos_;
        buffer_pos_ = 0;
    } else if (buffer_pos_ >= buffer_size_) {
        buffer_size_ = 0;
        buffer_pos_ = 0;
    }
}

// RESPSerializer implementation
RESPSerializer::RESPSerializer(size_t buffer_size) : buffer_(buffer_size) {
    buffer_.reserve(buffer_size);
}

void RESPSerializer::serialize(const RESPValue& value) {
    switch (value.type) {
        case RESPType::SimpleString:
            serialize_simple_string(std::get<std::string>(value.value));
            break;
        case RESPType::Error:
            serialize_error(std::get<std::string>(value.value));
            break;
        case RESPType::Integer:
            serialize_integer(std::get<int64_t>(value.value));
            break;
        case RESPType::BulkString:
            serialize_bulk_string(std::get<std::string>(value.value));
            break;
        case RESPType::Array:
            serialize_array(std::get<std::vector<RESPValue>>(value.value));
            break;
        case RESPType::Null:
            serialize_null_bulk_string();
            break;
        default:
            // Unsupported type, serialize as error
            serialize_error("Unsupported RESP type");
            break;
    }
}

void RESPSerializer::serialize_simple_string(const std::string& str) {
    append('+');
    append(str.data(), str.size());
    append_crlf();
}

void RESPSerializer::serialize_error(const std::string& error) {
    append('-');
    append(error.data(), error.size());
    append_crlf();
}

void RESPSerializer::serialize_integer(int64_t value) {
    append(':');
    append_integer(value);
    append_crlf();
}

void RESPSerializer::serialize_bulk_string(const std::string& str) {
    append('$');
    append_integer(str.size());
    append_crlf();
    append(str.data(), str.size());
    append_crlf();
}

void RESPSerializer::serialize_null_bulk_string() {
    append('$');
    append('-');
    append('1');
    append_crlf();
}

void RESPSerializer::serialize_array(const std::vector<RESPValue>& array) {
    append('*');
    append_integer(array.size());
    append_crlf();
    
    for (const auto& element : array) {
        serialize(element);
    }
}

void RESPSerializer::serialize_null_array() {
    append('*');
    append('-');
    append('1');
    append_crlf();
}

std::span<const char> RESPSerializer::data() const {
    return std::span<const char>(buffer_.data(), buffer_pos_);
}

void RESPSerializer::clear() {
    buffer_pos_ = 0;
}

std::string RESPSerializer::to_string() const {
    return std::string(buffer_.data(), buffer_pos_);
}

void RESPSerializer::ensure_capacity(size_t needed) {
    if (buffer_pos_ + needed > buffer_.size()) {
        size_t new_size = std::max(buffer_.size() * 2, buffer_pos_ + needed);
        if (new_size > MAX_BUFFER_SIZE) {
            throw std::runtime_error("Buffer size limit exceeded");
        }
        buffer_.resize(new_size);
    }
}

void RESPSerializer::append(const char* data, size_t length) {
    ensure_capacity(length);
    std::memcpy(buffer_.data() + buffer_pos_, data, length);
    buffer_pos_ += length;
}

void RESPSerializer::append(char c) {
    ensure_capacity(1);
    buffer_[buffer_pos_++] = c;
}

void RESPSerializer::append_crlf() {
    ensure_capacity(2);
    buffer_[buffer_pos_++] = '\r';
    buffer_[buffer_pos_++] = '\n';
}

void RESPSerializer::append_integer(int64_t value) {
    std::string str = std::to_string(value);
    append(str.data(), str.size());
}

// CommandParser implementation
std::optional<CommandParser::Command> CommandParser::parse_command(const RESPValue& value) {
    if (!is_valid_command(value)) {
        return std::nullopt;
    }
    
    const auto& array = std::get<std::vector<RESPValue>>(value.value);
    
    Command command;
    command.name = normalize_command_name(std::get<std::string>(array[0].value));
    
    command.args.reserve(array.size() - 1);
    for (size_t i = 1; i < array.size(); ++i) {
        command.args.push_back(std::get<std::string>(array[i].value));
    }
    
    return command;
}

bool CommandParser::is_valid_command(const RESPValue& value) {
    if (value.type != RESPType::Array) {
        return false;
    }
    
    const auto& array = std::get<std::vector<RESPValue>>(value.value);
    if (array.empty()) {
        return false;
    }
    
    // First element must be a bulk string (command name)
    if (array[0].type != RESPType::BulkString) {
        return false;
    }
    
    // All other elements must be bulk strings (arguments)
    for (size_t i = 1; i < array.size(); ++i) {
        if (array[i].type != RESPType::BulkString) {
            return false;
        }
    }
    
    return true;
}

std::string CommandParser::normalize_command_name(const std::string& name) {
    std::string result = name;
    std::transform(result.begin(), result.end(), result.begin(), ::toupper);
    return result;
}

} // namespace protocol
} // namespace meteor 