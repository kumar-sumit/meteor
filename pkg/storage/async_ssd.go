package storage

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

// AsyncSSDStorage implements high-performance SSD storage using io_uring/libaio
type AsyncSSDStorage struct {
	baseDir     string
	pageSize    int
	maxFileSize int64
	files       sync.Map
	ioBackend   IOBackend
	ioQueue     *IOQueue
	mu          sync.RWMutex
	metrics     *StorageMetrics
}

// IOBackend defines the interface for async I/O operations
type IOBackend interface {
	ReadAsync(fd int, offset int64, buf []byte) (*IORequest, error)
	WriteAsync(fd int, offset int64, buf []byte) (*IORequest, error)
	Submit(requests []*IORequest) error
	Poll(timeout time.Duration) ([]*IOCompletion, error)
	Close() error
}

// IORequest represents an asynchronous I/O request
type IORequest struct {
	ID       uint64
	Type     IOType
	FD       int
	Offset   int64
	Buffer   []byte
	Callback func(*IOCompletion)
	UserData interface{}
}

// IOCompletion represents a completed I/O operation
type IOCompletion struct {
	Request *IORequest
	Result  int
	Error   error
}

// IOType represents the type of I/O operation
type IOType int

const (
	IOTypeRead IOType = iota
	IOTypeWrite
)

// IOQueue manages asynchronous I/O operations
type IOQueue struct {
	backend     IOBackend
	pending     map[uint64]*IORequest
	completions chan *IOCompletion
	mu          sync.RWMutex
	nextID      uint64
	workers     int
	stopChan    chan struct{}
	wg          sync.WaitGroup
}

// StorageMetrics tracks storage performance metrics
type StorageMetrics struct {
	ReadLatency  *LatencyHistogram
	WriteLatency *LatencyHistogram
	QueueDepth   *Gauge
	IOErrors     *Counter
	BytesRead    *Counter
	BytesWritten *Counter
}

// NewAsyncSSDStorage creates a new async SSD storage instance
func NewAsyncSSDStorage(baseDir string, pageSize int, maxFileSize int64) (*AsyncSSDStorage, error) {
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base directory: %w", err)
	}

	// Try to initialize io_uring first, fallback to libaio
	var backend IOBackend
	var err error

	if backend, err = NewIOUringAdapter(256); err != nil {
		// Fallback to libaio
		if backend, err = NewLibAIOAdapter(256); err != nil {
			return nil, fmt.Errorf("failed to initialize async I/O backend: %w", err)
		}
	}

	ioQueue := &IOQueue{
		backend:     backend,
		pending:     make(map[uint64]*IORequest),
		completions: make(chan *IOCompletion, 1000),
		workers:     4, // Configurable
		stopChan:    make(chan struct{}),
	}

	storage := &AsyncSSDStorage{
		baseDir:     baseDir,
		pageSize:    pageSize,
		maxFileSize: maxFileSize,
		ioBackend:   backend,
		ioQueue:     ioQueue,
		metrics:     newStorageMetrics(),
	}

	// Start I/O workers
	for i := 0; i < ioQueue.workers; i++ {
		ioQueue.wg.Add(1)
		go storage.ioWorker()
	}

	return storage, nil
}

// ioWorker handles asynchronous I/O operations
func (s *AsyncSSDStorage) ioWorker() {
	defer s.ioQueue.wg.Done()

	for {
		select {
		case <-s.ioQueue.stopChan:
			return
		default:
			// Poll for completed I/O operations
			completions, err := s.ioBackend.Poll(time.Millisecond * 10)
			if err != nil {
				s.metrics.IOErrors.Inc()
				continue
			}

			for _, completion := range completions {
				s.ioQueue.mu.Lock()
				delete(s.ioQueue.pending, completion.Request.ID)
				s.ioQueue.mu.Unlock()

				// Execute callback if provided
				if completion.Request.Callback != nil {
					completion.Request.Callback(completion)
				}

				// Send to completion channel
				select {
				case s.ioQueue.completions <- completion:
				default:
					// Channel full, drop completion
				}
			}
		}
	}
}

// AsyncFile represents a file optimized for async I/O
type AsyncFile struct {
	path     string
	fd       int
	size     int64
	refCount int32
	mu       sync.RWMutex
}

// getOrCreateFile returns a file descriptor for async I/O
func (s *AsyncSSDStorage) getOrCreateFile(key string) (*AsyncFile, error) {
	fileName := s.getFileName(key)
	filePath := filepath.Join(s.baseDir, fileName)

	if value, ok := s.files.Load(fileName); ok {
		return value.(*AsyncFile), nil
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	// Double-check after acquiring lock
	if value, ok := s.files.Load(fileName); ok {
		return value.(*AsyncFile), nil
	}

	// Open file with O_DIRECT for better performance
	flags := syscall.O_RDWR | syscall.O_CREAT
	// O_DIRECT is not available on macOS, only use on Linux
	if runtime.GOOS == "linux" {
		flags |= 0x4000 // O_DIRECT on Linux
	}
	fd, err := syscall.Open(filePath, flags, 0644)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %w", err)
	}

	// Set file size
	if err := syscall.Ftruncate(fd, s.maxFileSize); err != nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("failed to set file size: %w", err)
	}

	asyncFile := &AsyncFile{
		path: filePath,
		fd:   fd,
		size: s.maxFileSize,
	}

	s.files.Store(fileName, asyncFile)
	return asyncFile, nil
}

// WriteAsync writes data asynchronously to SSD
func (s *AsyncSSDStorage) WriteAsync(key string, value []byte) error {
	start := time.Now()
	defer func() {
		s.metrics.WriteLatency.Observe(time.Since(start))
	}()

	file, err := s.getOrCreateFile(key)
	if err != nil {
		return err
	}

	position := s.calculatePosition(key)

	// Prepare data with alignment for O_DIRECT
	data := s.prepareAlignedData(key, value)

	// Create async write request
	req := &IORequest{
		ID:     s.getNextID(),
		Type:   IOTypeWrite,
		FD:     file.fd,
		Offset: int64(position),
		Buffer: data,
	}

	// Submit async write
	if err := s.ioBackend.Submit([]*IORequest{req}); err != nil {
		return fmt.Errorf("failed to submit write request: %w", err)
	}

	s.ioQueue.mu.Lock()
	s.ioQueue.pending[req.ID] = req
	s.ioQueue.mu.Unlock()

	s.metrics.BytesWritten.Add(float64(len(data)))
	return nil
}

// ReadAsync reads data asynchronously from SSD
func (s *AsyncSSDStorage) ReadAsync(key string) ([]byte, error) {
	start := time.Now()
	defer func() {
		s.metrics.ReadLatency.Observe(time.Since(start))
	}()

	file, err := s.getOrCreateFile(key)
	if err != nil {
		return nil, err
	}

	position := s.calculatePosition(key)

	// Allocate aligned buffer for O_DIRECT
	buffer := s.allocateAlignedBuffer(s.pageSize)

	// Create completion channel for this specific read
	done := make(chan *IOCompletion, 1)

	// Create async read request
	req := &IORequest{
		ID:     s.getNextID(),
		Type:   IOTypeRead,
		FD:     file.fd,
		Offset: int64(position),
		Buffer: buffer,
		Callback: func(completion *IOCompletion) {
			done <- completion
		},
	}

	// Submit async read
	if err := s.ioBackend.Submit([]*IORequest{req}); err != nil {
		return nil, fmt.Errorf("failed to submit read request: %w", err)
	}

	s.ioQueue.mu.Lock()
	s.ioQueue.pending[req.ID] = req
	s.ioQueue.mu.Unlock()

	// Wait for completion with timeout
	select {
	case completion := <-done:
		if completion.Error != nil {
			return nil, completion.Error
		}

		// Parse the data
		data, err := s.parseData(completion.Request.Buffer, key)
		if err != nil {
			return nil, err
		}

		s.metrics.BytesRead.Add(float64(len(data)))
		return data, nil

	case <-time.After(time.Second * 5):
		return nil, errors.New("read timeout")
	}
}

// prepareAlignedData prepares data with proper alignment for O_DIRECT
func (s *AsyncSSDStorage) prepareAlignedData(key string, value []byte) []byte {
	keyBytes := []byte(key)

	// Calculate required size with headers
	dataSize := 4 + 4 + 8 + 4 + len(keyBytes) + len(value)

	// Align to page boundary for O_DIRECT
	alignedSize := ((dataSize + s.pageSize - 1) / s.pageSize) * s.pageSize

	// Allocate aligned buffer
	buffer := s.allocateAlignedBuffer(alignedSize)

	offset := 0

	// Write headers
	*(*uint32)(unsafe.Pointer(&buffer[offset])) = uint32(len(keyBytes))
	offset += 4

	*(*uint32)(unsafe.Pointer(&buffer[offset])) = uint32(len(value))
	offset += 4

	*(*uint64)(unsafe.Pointer(&buffer[offset])) = uint64(time.Now().Unix())
	offset += 8

	*(*uint32)(unsafe.Pointer(&buffer[offset])) = uint32(3600) // TTL
	offset += 4

	// Write key and value
	copy(buffer[offset:], keyBytes)
	offset += len(keyBytes)
	copy(buffer[offset:], value)

	return buffer
}

// allocateAlignedBuffer allocates a buffer aligned to page boundaries
func (s *AsyncSSDStorage) allocateAlignedBuffer(size int) []byte {
	// Allocate extra space for alignment
	buf := make([]byte, size+s.pageSize)

	// Calculate aligned address
	addr := uintptr(unsafe.Pointer(&buf[0]))
	aligned := (addr + uintptr(s.pageSize-1)) & ^uintptr(s.pageSize-1)
	offset := aligned - addr

	return buf[offset : offset+uintptr(size)]
}

// parseData parses data from aligned buffer
func (s *AsyncSSDStorage) parseData(buffer []byte, expectedKey string) ([]byte, error) {
	if len(buffer) < 20 {
		return nil, errors.New("invalid data format")
	}

	offset := 0

	// Read headers
	keyLen := *(*uint32)(unsafe.Pointer(&buffer[offset]))
	offset += 4

	valueLen := *(*uint32)(unsafe.Pointer(&buffer[offset]))
	offset += 4

	// Skip timestamp and TTL
	offset += 12

	// Verify key
	if offset+int(keyLen) > len(buffer) {
		return nil, errors.New("corrupted data")
	}

	key := string(buffer[offset : offset+int(keyLen)])
	if key != expectedKey {
		return nil, nil // Key not found
	}
	offset += int(keyLen)

	// Read value
	if offset+int(valueLen) > len(buffer) {
		return nil, errors.New("corrupted data")
	}

	value := make([]byte, valueLen)
	copy(value, buffer[offset:offset+int(valueLen)])

	return value, nil
}

// getFileName returns the file name for a given key
func (s *AsyncSSDStorage) getFileName(key string) string {
	hash := uint32(0)
	for i := 0; i < len(key); i++ {
		hash = hash*31 + uint32(key[i])
	}
	return fmt.Sprintf("cache_%d.dat", hash%uint32(s.maxFileSize/int64(s.pageSize)))
}

// calculatePosition calculates the position in the file for a given key
func (s *AsyncSSDStorage) calculatePosition(key string) int {
	hash := uint32(0)
	for i := 0; i < len(key); i++ {
		hash = hash*31 + uint32(key[i])
	}
	return int(hash%uint32(s.maxFileSize/int64(s.pageSize))) * s.pageSize
}

// getNextID generates a unique ID for I/O requests
func (s *AsyncSSDStorage) getNextID() uint64 {
	s.ioQueue.mu.Lock()
	defer s.ioQueue.mu.Unlock()
	s.ioQueue.nextID++
	return s.ioQueue.nextID
}

// Close closes the storage and releases resources
func (s *AsyncSSDStorage) Close() error {
	close(s.ioQueue.stopChan)
	s.ioQueue.wg.Wait()

	// Close all files
	s.files.Range(func(key, value interface{}) bool {
		if file, ok := value.(*AsyncFile); ok {
			syscall.Close(file.fd)
		}
		return true
	})

	return s.ioBackend.Close()
}

// GetMetrics returns storage metrics
func (s *AsyncSSDStorage) GetMetrics() *StorageMetrics {
	return s.metrics
}

// newStorageMetrics creates a new metrics instance
func newStorageMetrics() *StorageMetrics {
	return &StorageMetrics{
		ReadLatency:  NewLatencyHistogram(),
		WriteLatency: NewLatencyHistogram(),
		QueueDepth:   NewGauge(),
		IOErrors:     NewCounter(),
		BytesRead:    NewCounter(),
		BytesWritten: NewCounter(),
	}
}
