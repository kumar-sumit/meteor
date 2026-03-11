package server

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"sync"
	"unsafe"
)

// RESPType represents the type of RESP data
type RESPType byte

const (
	SimpleString RESPType = '+'
	Error        RESPType = '-'
	Integer      RESPType = ':'
	BulkString   RESPType = '$'
	Array        RESPType = '*'
)

// RESPValue represents a parsed RESP value
type RESPValue struct {
	Type  RESPType
	Str   string
	Int   int64
	Array []RESPValue
	Null  bool
}

// Pool for reusing byte slices
var byteSlicePool = sync.Pool{
	New: func() interface{} {
		return make([]byte, 0, 1024)
	},
}

// Pool for reusing RESPValue arrays
var respValuePool = sync.Pool{
	New: func() interface{} {
		return make([]RESPValue, 0, 16)
	},
}

// RESPParser handles parsing RESP protocol messages
type RESPParser struct {
	reader *bufio.Reader
	buf    []byte
}

// NewRESPParser creates a new RESP parser
func NewRESPParser(reader io.Reader) *RESPParser {
	return &RESPParser{
		reader: bufio.NewReaderSize(reader, 32*1024), // 32KB buffer for better performance
		buf:    make([]byte, 0, 1024),
	}
}

// Parse parses the next RESP value from the reader
func (p *RESPParser) Parse() (*RESPValue, error) {
	typeByte, err := p.reader.ReadByte()
	if err != nil {
		return nil, err
	}

	switch RESPType(typeByte) {
	case SimpleString:
		return p.parseSimpleString()
	case Error:
		return p.parseError()
	case Integer:
		return p.parseInteger()
	case BulkString:
		return p.parseBulkString()
	case Array:
		return p.parseArray()
	default:
		return nil, fmt.Errorf("unknown RESP type: %c", typeByte)
	}
}

// parseSimpleString parses a simple string (+OK\r\n)
func (p *RESPParser) parseSimpleString() (*RESPValue, error) {
	line, err := p.readLine()
	if err != nil {
		return nil, err
	}
	return &RESPValue{Type: SimpleString, Str: line}, nil
}

// parseError parses an error (-ERR message\r\n)
func (p *RESPParser) parseError() (*RESPValue, error) {
	line, err := p.readLine()
	if err != nil {
		return nil, err
	}
	return &RESPValue{Type: Error, Str: line}, nil
}

// parseInteger parses an integer (:1000\r\n)
func (p *RESPParser) parseInteger() (*RESPValue, error) {
	line, err := p.readLine()
	if err != nil {
		return nil, err
	}

	num, err := strconv.ParseInt(line, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid integer: %s", line)
	}

	return &RESPValue{Type: Integer, Int: num}, nil
}

// parseBulkString parses a bulk string ($6\r\nfoobar\r\n)
func (p *RESPParser) parseBulkString() (*RESPValue, error) {
	line, err := p.readLineFast()
	if err != nil {
		return nil, err
	}

	length, err := parseInt64(line)
	if err != nil {
		return nil, fmt.Errorf("invalid bulk string length: %s", line)
	}

	if length == -1 {
		return &RESPValue{Type: BulkString, Null: true}, nil
	}

	if length < 0 {
		return nil, fmt.Errorf("invalid bulk string length: %d", length)
	}

	// Read the bulk string data
	data := make([]byte, length)
	_, err = io.ReadFull(p.reader, data)
	if err != nil {
		return nil, fmt.Errorf("failed to read bulk string data: %v", err)
	}

	// Read the trailing \r\n
	_, err = p.reader.ReadByte() // \r
	if err != nil {
		return nil, fmt.Errorf("expected \\r after bulk string: %v", err)
	}
	_, err = p.reader.ReadByte() // \n
	if err != nil {
		return nil, fmt.Errorf("expected \\n after bulk string: %v", err)
	}

	return &RESPValue{Type: BulkString, Str: string(data)}, nil
}

// parseArray parses an array (*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n)
func (p *RESPParser) parseArray() (*RESPValue, error) {
	line, err := p.readLineFast()
	if err != nil {
		return nil, err
	}

	length, err := parseInt64(line)
	if err != nil {
		return nil, fmt.Errorf("invalid array length: %s", line)
	}

	if length == -1 {
		return &RESPValue{Type: Array, Null: true}, nil
	}

	if length < 0 {
		return nil, fmt.Errorf("invalid array length: %d", length)
	}

	// Use pool for better performance
	array := respValuePool.Get().([]RESPValue)
	array = array[:0] // Reset length but keep capacity

	defer func() {
		// Return to pool if capacity is reasonable
		if cap(array) <= 64 {
			respValuePool.Put(array)
		}
	}()

	for i := int64(0); i < length; i++ {
		value, err := p.Parse()
		if err != nil {
			return nil, fmt.Errorf("failed to parse array element %d: %v", i, err)
		}
		array = append(array, *value)
	}

	// Create a new slice to avoid pool interference
	result := make([]RESPValue, len(array))
	copy(result, array)

	return &RESPValue{Type: Array, Array: result}, nil
}

// readLineFast reads a line more efficiently using byte slices
func (p *RESPParser) readLineFast() ([]byte, error) {
	p.buf = p.buf[:0] // Reset buffer

	for {
		line, err := p.reader.ReadSlice('\n')
		if err != nil {
			if err == bufio.ErrBufferFull {
				// Buffer is full, append to our buffer and continue
				p.buf = append(p.buf, line...)
				continue
			}
			return nil, err
		}

		// Append the final part
		p.buf = append(p.buf, line...)

		// Remove \r\n from the end
		if len(p.buf) >= 2 && p.buf[len(p.buf)-2] == '\r' && p.buf[len(p.buf)-1] == '\n' {
			return p.buf[:len(p.buf)-2], nil
		}

		return nil, fmt.Errorf("invalid line ending")
	}
}

// parseInt64 parses int64 from byte slice more efficiently
func parseInt64(b []byte) (int64, error) {
	if len(b) == 0 {
		return 0, fmt.Errorf("empty string")
	}

	var neg bool
	var result int64
	i := 0

	if b[0] == '-' {
		neg = true
		i = 1
	} else if b[0] == '+' {
		i = 1
	}

	for ; i < len(b); i++ {
		if b[i] < '0' || b[i] > '9' {
			return 0, fmt.Errorf("invalid digit")
		}
		result = result*10 + int64(b[i]-'0')
	}

	if neg {
		result = -result
	}

	return result, nil
}

// unsafeString converts byte slice to string without allocation
func unsafeString(b []byte) string {
	return *(*string)(unsafe.Pointer(&b))
}

// readLine reads a line ending with \r\n
func (p *RESPParser) readLine() (string, error) {
	line, err := p.reader.ReadString('\n')
	if err != nil {
		return "", err
	}

	// Remove \r\n
	if len(line) >= 2 && line[len(line)-2:] == "\r\n" {
		return line[:len(line)-2], nil
	}

	// Try just \n
	if len(line) >= 1 && line[len(line)-1:] == "\n" {
		return line[:len(line)-1], nil
	}

	return line, nil
}

// RESPSerializer handles serializing RESP protocol messages
type RESPSerializer struct {
	writer *bufio.Writer
	buf    []byte
}

// NewRESPSerializer creates a new RESP serializer
func NewRESPSerializer(writer io.Writer) *RESPSerializer {
	return &RESPSerializer{
		writer: bufio.NewWriterSize(writer, 32*1024), // 32KB buffer
		buf:    make([]byte, 0, 1024),
	}
}

// Flush flushes the underlying buffer
func (s *RESPSerializer) Flush() error {
	return s.writer.Flush()
}

// WriteSimpleString writes a simple string (+OK\r\n)
func (s *RESPSerializer) WriteSimpleString(str string) error {
	s.buf = s.buf[:0]
	s.buf = append(s.buf, '+')
	s.buf = append(s.buf, str...)
	s.buf = append(s.buf, '\r', '\n')
	_, err := s.writer.Write(s.buf)
	return err
}

// WriteError writes an error (-ERR message\r\n)
func (s *RESPSerializer) WriteError(message string) error {
	s.buf = s.buf[:0]
	s.buf = append(s.buf, '-')
	s.buf = append(s.buf, message...)
	s.buf = append(s.buf, '\r', '\n')
	_, err := s.writer.Write(s.buf)
	return err
}

// WriteInteger writes an integer (:1000\r\n)
func (s *RESPSerializer) WriteInteger(num int64) error {
	s.buf = s.buf[:0]
	s.buf = append(s.buf, ':')
	s.buf = strconv.AppendInt(s.buf, num, 10)
	s.buf = append(s.buf, '\r', '\n')
	_, err := s.writer.Write(s.buf)
	return err
}

// WriteBulkString writes a bulk string ($6\r\nfoobar\r\n)
func (s *RESPSerializer) WriteBulkString(str string) error {
	s.buf = s.buf[:0]
	s.buf = append(s.buf, '$')
	s.buf = strconv.AppendInt(s.buf, int64(len(str)), 10)
	s.buf = append(s.buf, '\r', '\n')
	s.buf = append(s.buf, str...)
	s.buf = append(s.buf, '\r', '\n')
	_, err := s.writer.Write(s.buf)
	return err
}

// WriteNullBulkString writes a null bulk string ($-1\r\n)
func (s *RESPSerializer) WriteNullBulkString() error {
	_, err := s.writer.Write([]byte("$-1\r\n"))
	return err
}

// WriteArray writes an array (*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n)
func (s *RESPSerializer) WriteArray(values []RESPValue) error {
	s.buf = s.buf[:0]
	s.buf = append(s.buf, '*')
	s.buf = strconv.AppendInt(s.buf, int64(len(values)), 10)
	s.buf = append(s.buf, '\r', '\n')

	if _, err := s.writer.Write(s.buf); err != nil {
		return err
	}

	for _, value := range values {
		if err := s.WriteValue(value); err != nil {
			return err
		}
	}

	return nil
}

// WriteNullArray writes a null array (*-1\r\n)
func (s *RESPSerializer) WriteNullArray() error {
	_, err := s.writer.Write([]byte("*-1\r\n"))
	return err
}

// WriteValue writes a RESP value
func (s *RESPSerializer) WriteValue(value RESPValue) error {
	switch value.Type {
	case SimpleString:
		return s.WriteSimpleString(value.Str)
	case Error:
		return s.WriteError(value.Str)
	case Integer:
		return s.WriteInteger(value.Int)
	case BulkString:
		if value.Null {
			return s.WriteNullBulkString()
		}
		return s.WriteBulkString(value.Str)
	case Array:
		if value.Null {
			return s.WriteNullArray()
		}
		return s.WriteArray(value.Array)
	default:
		return fmt.Errorf("unknown RESP type: %d", value.Type)
	}
}
