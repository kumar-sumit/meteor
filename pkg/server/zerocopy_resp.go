package server

import (
	"bufio"
	"errors"
	"io"
	"strconv"
	"sync"
	"unsafe"
)

// ZeroCopyRESPParser implements zero-copy RESP parsing with enhanced performance
type ZeroCopyRESPParser struct {
	reader     *bufio.Reader
	buf        []byte
	pool       *sync.Pool
	lineBuffer []byte

	// Performance optimizations
	bufferSize   int
	reuseBuffers bool
	parseBuffer  []byte
	arrayPool    *sync.Pool
	stringPool   *sync.Pool
}

// ZeroCopyRESPValue represents a RESP value with zero-copy semantics
type ZeroCopyRESPValue struct {
	Type     RESPType
	Data     []byte // Raw data without copying
	Int      int64
	Array    []ZeroCopyRESPValue
	Null     bool
	dataPool *sync.Pool // Pool for returning data buffers

	// Performance optimizations
	refCount int32
	pooled   bool
}

// String returns the string representation with zero-copy when possible
func (v *ZeroCopyRESPValue) String() string {
	if v.Data == nil {
		return ""
	}
	// Use unsafe pointer conversion for zero-copy string creation
	return *(*string)(unsafe.Pointer(&v.Data))
}

// StringUnsafe returns unsafe string reference (faster but requires careful lifetime management)
func (v *ZeroCopyRESPValue) StringUnsafe() string {
	if v.Data == nil {
		return ""
	}
	return *(*string)(unsafe.Pointer(&v.Data))
}

// Bytes returns the raw bytes without copying
func (v *ZeroCopyRESPValue) Bytes() []byte {
	return v.Data
}

// Release returns the value's resources to the pool
func (v *ZeroCopyRESPValue) Release() {
	if v.dataPool != nil && v.Data != nil && v.pooled {
		v.dataPool.Put(v.Data[:0])
	}
	for i := range v.Array {
		v.Array[i].Release()
	}
	if len(v.Array) > 0 {
		RESPValuePool.Put(v.Array[:0])
	}
	v.Array = nil
	v.Data = nil
	v.pooled = false
}

// Enhanced buffer pools with size-based pooling
var (
	// Small buffer pool (up to 1KB)
	SmallBufferPool = &sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 1024)
		},
	}

	// Medium buffer pool (up to 8KB)
	MediumBufferPool = &sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 8192)
		},
	}

	// Large buffer pool (up to 64KB)
	LargeBufferPool = &sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 65536)
		},
	}

	// ByteSlicePool manages reusable byte slices
	ByteSlicePool = &sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 1024)
		},
	}

	// RESPValuePool manages reusable RESP value arrays
	RESPValuePool = &sync.Pool{
		New: func() interface{} {
			return make([]ZeroCopyRESPValue, 0, 16)
		},
	}

	// StringPool manages reusable strings
	StringPool = &sync.Pool{
		New: func() interface{} {
			return make([]string, 0, 16)
		},
	}
)

// getBufferPool returns the appropriate buffer pool based on size
func getBufferPool(size int) *sync.Pool {
	if size <= 1024 {
		return SmallBufferPool
	} else if size <= 8192 {
		return MediumBufferPool
	} else {
		return LargeBufferPool
	}
}

// NewZeroCopyRESPParser creates a new zero-copy RESP parser with optimizations
func NewZeroCopyRESPParser(reader io.Reader) *ZeroCopyRESPParser {
	bufferSize := 64 * 1024 // 64KB buffer

	return &ZeroCopyRESPParser{
		reader:       bufio.NewReaderSize(reader, bufferSize),
		buf:          make([]byte, 0, 4096),
		pool:         ByteSlicePool,
		lineBuffer:   make([]byte, 0, 512),
		bufferSize:   bufferSize,
		reuseBuffers: true,
		parseBuffer:  make([]byte, 0, 1024),
		arrayPool:    RESPValuePool,
		stringPool:   StringPool,
	}
}

// Parse parses the next RESP value with zero-copy semantics
func (p *ZeroCopyRESPParser) Parse() (*ZeroCopyRESPValue, error) {
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
		return nil, errors.New("unknown RESP type")
	}
}

// parseSimpleString parses a simple string with zero-copy optimizations
func (p *ZeroCopyRESPParser) parseSimpleString() (*ZeroCopyRESPValue, error) {
	data, err := p.readLineZeroCopyOptimized()
	if err != nil {
		return nil, err
	}

	return &ZeroCopyRESPValue{
		Type:     SimpleString,
		Data:     data,
		dataPool: p.pool,
		pooled:   true,
	}, nil
}

// parseError parses an error with zero-copy optimizations
func (p *ZeroCopyRESPParser) parseError() (*ZeroCopyRESPValue, error) {
	data, err := p.readLineZeroCopyOptimized()
	if err != nil {
		return nil, err
	}

	return &ZeroCopyRESPValue{
		Type:     Error,
		Data:     data,
		dataPool: p.pool,
		pooled:   true,
	}, nil
}

// parseInteger parses an integer with optimized number parsing
func (p *ZeroCopyRESPParser) parseInteger() (*ZeroCopyRESPValue, error) {
	data, err := p.readLineZeroCopyOptimized()
	if err != nil {
		return nil, err
	}

	num, err := parseIntFromBytesOptimized(data)
	if err != nil {
		p.pool.Put(data[:0])
		return nil, err
	}

	// Return data to pool since we extracted the integer
	p.pool.Put(data[:0])

	return &ZeroCopyRESPValue{
		Type: Integer,
		Int:  num,
	}, nil
}

// parseBulkString parses a bulk string with zero-copy and buffer reuse
func (p *ZeroCopyRESPParser) parseBulkString() (*ZeroCopyRESPValue, error) {
	lengthData, err := p.readLineZeroCopyOptimized()
	if err != nil {
		return nil, err
	}

	length, err := parseIntFromBytesOptimized(lengthData)
	p.pool.Put(lengthData[:0]) // Return length data to pool

	if err != nil {
		return nil, err
	}

	if length == -1 {
		return &ZeroCopyRESPValue{Type: BulkString, Null: true}, nil
	}

	if length < 0 {
		return nil, errors.New("invalid bulk string length")
	}

	// Use appropriate buffer pool based on size
	pool := getBufferPool(int(length))
	data := pool.Get().([]byte)

	if cap(data) < int(length) {
		data = make([]byte, length)
	} else {
		data = data[:length]
	}

	_, err = io.ReadFull(p.reader, data)
	if err != nil {
		pool.Put(data[:0])
		return nil, err
	}

	// Read trailing \r\n efficiently
	if err = p.skipCRLF(); err != nil {
		pool.Put(data[:0])
		return nil, err
	}

	return &ZeroCopyRESPValue{
		Type:     BulkString,
		Data:     data,
		dataPool: pool,
		pooled:   true,
	}, nil
}

// parseArray parses an array with zero-copy and optimized array handling
func (p *ZeroCopyRESPParser) parseArray() (*ZeroCopyRESPValue, error) {
	lengthData, err := p.readLineZeroCopyOptimized()
	if err != nil {
		return nil, err
	}

	length, err := parseIntFromBytesOptimized(lengthData)
	p.pool.Put(lengthData[:0]) // Return length data to pool

	if err != nil {
		return nil, err
	}

	if length == -1 {
		return &ZeroCopyRESPValue{Type: Array, Null: true}, nil
	}

	if length < 0 {
		return nil, errors.New("invalid array length")
	}

	// Get array from pool
	array := p.arrayPool.Get().([]ZeroCopyRESPValue)
	if cap(array) < int(length) {
		array = make([]ZeroCopyRESPValue, length)
	} else {
		array = array[:length]
	}

	// Parse array elements
	for i := int64(0); i < length; i++ {
		elem, err := p.Parse()
		if err != nil {
			// Clean up parsed elements
			for j := int64(0); j < i; j++ {
				array[j].Release()
			}
			p.arrayPool.Put(array[:0])
			return nil, err
		}
		array[i] = *elem
	}

	return &ZeroCopyRESPValue{
		Type:  Array,
		Array: array,
	}, nil
}

// readLineZeroCopyOptimized reads a line with optimized zero-copy approach
func (p *ZeroCopyRESPParser) readLineZeroCopyOptimized() ([]byte, error) {
	// Try to read from buffered data first
	if p.reader.Buffered() > 0 {
		line, err := p.reader.ReadSlice('\n')
		if err == nil {
			// Remove \r\n
			if len(line) >= 2 && line[len(line)-2] == '\r' {
				line = line[:len(line)-2]
			} else if len(line) >= 1 && line[len(line)-1] == '\n' {
				line = line[:len(line)-1]
			}

			// Copy to managed buffer
			data := p.pool.Get().([]byte)
			if cap(data) < len(line) {
				data = make([]byte, len(line))
			} else {
				data = data[:len(line)]
			}
			copy(data, line)
			return data, nil
		}
	}

	// Fallback to regular line reading
	return p.readLineZeroCopy()
}

// readLineZeroCopy reads a line with zero-copy semantics
func (p *ZeroCopyRESPParser) readLineZeroCopy() ([]byte, error) {
	p.lineBuffer = p.lineBuffer[:0]

	for {
		b, err := p.reader.ReadByte()
		if err != nil {
			return nil, err
		}

		if b == '\r' {
			// Peek next byte
			next, err := p.reader.ReadByte()
			if err != nil {
				return nil, err
			}
			if next == '\n' {
				break
			}
			// Not CRLF, add both bytes
			p.lineBuffer = append(p.lineBuffer, b, next)
		} else if b == '\n' {
			break
		} else {
			p.lineBuffer = append(p.lineBuffer, b)
		}
	}

	// Copy to managed buffer
	data := p.pool.Get().([]byte)
	if cap(data) < len(p.lineBuffer) {
		data = make([]byte, len(p.lineBuffer))
	} else {
		data = data[:len(p.lineBuffer)]
	}
	copy(data, p.lineBuffer)

	return data, nil
}

// skipCRLF efficiently skips \r\n
func (p *ZeroCopyRESPParser) skipCRLF() error {
	b1, err := p.reader.ReadByte()
	if err != nil {
		return err
	}
	if b1 != '\r' {
		return errors.New("expected \\r")
	}

	b2, err := p.reader.ReadByte()
	if err != nil {
		return err
	}
	if b2 != '\n' {
		return errors.New("expected \\n")
	}

	return nil
}

// parseIntFromBytesOptimized parses integer from bytes with optimizations
func parseIntFromBytesOptimized(data []byte) (int64, error) {
	if len(data) == 0 {
		return 0, errors.New("empty data")
	}

	var result int64
	var negative bool
	i := 0

	// Handle sign
	if data[0] == '-' {
		negative = true
		i = 1
	} else if data[0] == '+' {
		i = 1
	}

	// Parse digits
	for i < len(data) {
		if data[i] < '0' || data[i] > '9' {
			return 0, errors.New("invalid integer")
		}
		result = result*10 + int64(data[i]-'0')
		i++
	}

	if negative {
		result = -result
	}

	return result, nil
}

// parseIntFromBytes parses integer from bytes (fallback)
func parseIntFromBytes(data []byte) (int64, error) {
	return strconv.ParseInt(string(data), 10, 64)
}

// ZeroCopyRESPSerializer implements zero-copy RESP serialization
type ZeroCopyRESPSerializer struct {
	writer      io.Writer
	buf         []byte
	pool        *sync.Pool
	writeBuffer []byte

	// Performance optimizations
	bufferSize  int
	batchWrites bool
}

// NewZeroCopyRESPSerializer creates a new zero-copy RESP serializer
func NewZeroCopyRESPSerializer(writer io.Writer) *ZeroCopyRESPSerializer {
	return &ZeroCopyRESPSerializer{
		writer:      writer,
		buf:         make([]byte, 0, 1024),
		pool:        ByteSlicePool,
		writeBuffer: make([]byte, 0, 4096),
		bufferSize:  4096,
		batchWrites: true,
	}
}

// WriteSimpleString writes a simple string with zero-copy
func (s *ZeroCopyRESPSerializer) WriteSimpleString(str string) error {
	s.writeBuffer = s.writeBuffer[:0]
	s.writeBuffer = append(s.writeBuffer, '+')
	s.writeBuffer = append(s.writeBuffer, str...)
	s.writeBuffer = append(s.writeBuffer, '\r', '\n')
	_, err := s.writer.Write(s.writeBuffer)
	return err
}

// WriteError writes an error with zero-copy
func (s *ZeroCopyRESPSerializer) WriteError(msg string) error {
	s.writeBuffer = s.writeBuffer[:0]
	s.writeBuffer = append(s.writeBuffer, '-')
	s.writeBuffer = append(s.writeBuffer, msg...)
	s.writeBuffer = append(s.writeBuffer, '\r', '\n')
	_, err := s.writer.Write(s.writeBuffer)
	return err
}

// WriteInteger writes an integer with optimized formatting
func (s *ZeroCopyRESPSerializer) WriteInteger(num int64) error {
	s.writeBuffer = s.writeBuffer[:0]
	s.writeBuffer = append(s.writeBuffer, ':')
	s.writeBuffer = appendInt(s.writeBuffer, num)
	s.writeBuffer = append(s.writeBuffer, '\r', '\n')
	_, err := s.writer.Write(s.writeBuffer)
	return err
}

// WriteBulkString writes a bulk string with zero-copy
func (s *ZeroCopyRESPSerializer) WriteBulkString(data []byte) error {
	s.writeBuffer = s.writeBuffer[:0]
	s.writeBuffer = append(s.writeBuffer, '$')
	s.writeBuffer = appendInt(s.writeBuffer, int64(len(data)))
	s.writeBuffer = append(s.writeBuffer, '\r', '\n')

	// Write header
	if _, err := s.writer.Write(s.writeBuffer); err != nil {
		return err
	}

	// Write data directly (zero-copy)
	if _, err := s.writer.Write(data); err != nil {
		return err
	}

	// Write trailing CRLF
	_, err := s.writer.Write([]byte{'\r', '\n'})
	return err
}

// WriteNullBulkString writes a null bulk string
func (s *ZeroCopyRESPSerializer) WriteNullBulkString() error {
	_, err := s.writer.Write([]byte("$-1\r\n"))
	return err
}

// WriteArray writes an array with zero-copy
func (s *ZeroCopyRESPSerializer) WriteArray(length int64) error {
	s.writeBuffer = s.writeBuffer[:0]
	s.writeBuffer = append(s.writeBuffer, '*')
	s.writeBuffer = appendInt(s.writeBuffer, length)
	s.writeBuffer = append(s.writeBuffer, '\r', '\n')
	_, err := s.writer.Write(s.writeBuffer)
	return err
}

// WriteNullArray writes a null array
func (s *ZeroCopyRESPSerializer) WriteNullArray() error {
	_, err := s.writer.Write([]byte("*-1\r\n"))
	return err
}

// appendInt appends an integer to a byte slice efficiently
func appendInt(buf []byte, num int64) []byte {
	if num == 0 {
		return append(buf, '0')
	}

	if num < 0 {
		buf = append(buf, '-')
		num = -num
	}

	// Convert to string representation
	start := len(buf)
	for num > 0 {
		buf = append(buf, byte('0'+num%10))
		num /= 10
	}

	// Reverse the digits
	end := len(buf) - 1
	for i := start; i < start+(end-start+1)/2; i++ {
		buf[i], buf[end-(i-start)] = buf[end-(i-start)], buf[i]
	}

	return buf
}

// GetStats returns parser statistics
func (p *ZeroCopyRESPParser) GetStats() map[string]interface{} {
	return map[string]interface{}{
		"buffer_size":      p.bufferSize,
		"reuse_buffers":    p.reuseBuffers,
		"reader_buffered":  p.reader.Buffered(),
		"line_buffer_cap":  cap(p.lineBuffer),
		"parse_buffer_cap": cap(p.parseBuffer),
	}
}
