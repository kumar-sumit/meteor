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

// OptimizedSSDStorage implements high-performance SSD storage with O_DIRECT
type OptimizedSSDStorage struct {
	baseDir     string
	pageSize    int
	maxFileSize int64
	files       sync.Map
	workers     int
	workQueue   chan *IOTask
	stopChan    chan struct{}
	wg          sync.WaitGroup
	metrics     *StorageMetrics
	mu          sync.RWMutex
}

// IOTask represents an I/O operation to be performed
type IOTask struct {
	Type     IOTaskType
	Key      string
	Value    []byte
	FD       int
	Offset   int64
	Buffer   []byte
	Response chan *IOResponse
}

// IOResponse represents the result of an I/O operation
type IOResponse struct {
	Data  []byte
	Error error
}

// IOTaskType represents the type of I/O operation
type IOTaskType int

const (
	IOTaskRead IOTaskType = iota
	IOTaskWrite
)

// OptimizedFile represents a file optimized for direct I/O
type OptimizedFile struct {
	path     string
	fd       int
	size     int64
	refCount int32
	mu       sync.RWMutex
}

// NewOptimizedSSDStorage creates a new optimized SSD storage instance
func NewOptimizedSSDStorage(baseDir string, pageSize int, maxFileSize int64) (*OptimizedSSDStorage, error) {
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base directory: %w", err)
	}

	workers := runtime.NumCPU() * 2 // 2 workers per CPU core
	if workers < 4 {
		workers = 4
	}

	storage := &OptimizedSSDStorage{
		baseDir:     baseDir,
		pageSize:    pageSize,
		maxFileSize: maxFileSize,
		workers:     workers,
		workQueue:   make(chan *IOTask, 1000),
		stopChan:    make(chan struct{}),
		metrics:     newStorageMetrics(),
	}

	// Start I/O workers
	for i := 0; i < workers; i++ {
		storage.wg.Add(1)
		go storage.ioWorker()
	}

	return storage, nil
}

// ioWorker processes I/O tasks from the queue
func (s *OptimizedSSDStorage) ioWorker() {
	defer s.wg.Done()

	for {
		select {
		case task := <-s.workQueue:
			s.processIOTask(task)
		case <-s.stopChan:
			return
		}
	}
}

// processIOTask processes a single I/O task
func (s *OptimizedSSDStorage) processIOTask(task *IOTask) {
	var response *IOResponse

	switch task.Type {
	case IOTaskRead:
		data, err := s.performRead(task.Key)
		response = &IOResponse{Data: data, Error: err}
	case IOTaskWrite:
		err := s.performWrite(task.Key, task.Value)
		response = &IOResponse{Error: err}
	}

	select {
	case task.Response <- response:
	case <-time.After(time.Second):
		// Response channel timeout
	}
}

// WriteAsync writes data asynchronously to SSD
func (s *OptimizedSSDStorage) WriteAsync(key string, value []byte) error {
	task := &IOTask{
		Type:     IOTaskWrite,
		Key:      key,
		Value:    value,
		Response: make(chan *IOResponse, 1),
	}

	select {
	case s.workQueue <- task:
		// Task queued successfully
		return nil
	case <-time.After(time.Millisecond * 100):
		return errors.New("write queue full")
	}
}

// ReadAsync reads data asynchronously from SSD
func (s *OptimizedSSDStorage) ReadAsync(key string) ([]byte, error) {
	task := &IOTask{
		Type:     IOTaskRead,
		Key:      key,
		Response: make(chan *IOResponse, 1),
	}

	select {
	case s.workQueue <- task:
		// Wait for response
		select {
		case response := <-task.Response:
			return response.Data, response.Error
		case <-time.After(time.Second * 5):
			return nil, errors.New("read timeout")
		}
	case <-time.After(time.Millisecond * 100):
		return nil, errors.New("read queue full")
	}
}

// performWrite performs the actual write operation
func (s *OptimizedSSDStorage) performWrite(key string, value []byte) error {
	start := time.Now()
	defer func() {
		s.metrics.WriteLatency.Observe(time.Since(start))
	}()

	file, err := s.getOrCreateFile(key)
	if err != nil {
		return err
	}

	position := s.calculatePosition(key)

	// Prepare aligned data for O_DIRECT
	alignedData := s.prepareAlignedData(key, value)

	// Perform direct write
	n, err := syscall.Pwrite(file.fd, alignedData, int64(position))
	if err != nil {
		s.metrics.IOErrors.Inc()
		return fmt.Errorf("write failed: %w", err)
	}

	if n != len(alignedData) {
		s.metrics.IOErrors.Inc()
		return errors.New("incomplete write")
	}

	s.metrics.BytesWritten.Add(float64(len(alignedData)))
	return nil
}

// performRead performs the actual read operation
func (s *OptimizedSSDStorage) performRead(key string) ([]byte, error) {
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

	// Perform direct read
	n, err := syscall.Pread(file.fd, buffer, int64(position))
	if err != nil {
		s.metrics.IOErrors.Inc()
		return nil, fmt.Errorf("read failed: %w", err)
	}

	if n == 0 {
		return nil, nil // Key not found
	}

	// Parse the data
	data, err := s.parseData(buffer[:n], key)
	if err != nil {
		return nil, err
	}

	s.metrics.BytesRead.Add(float64(n))
	return data, nil
}

// getOrCreateFile returns a file descriptor optimized for direct I/O
func (s *OptimizedSSDStorage) getOrCreateFile(key string) (*OptimizedFile, error) {
	fileName := s.getFileName(key)
	filePath := filepath.Join(s.baseDir, fileName)

	if value, ok := s.files.Load(fileName); ok {
		return value.(*OptimizedFile), nil
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	// Double-check after acquiring lock
	if value, ok := s.files.Load(fileName); ok {
		return value.(*OptimizedFile), nil
	}

	// Open file with O_DIRECT for better performance
	flags := syscall.O_RDWR | syscall.O_CREAT
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

	optimizedFile := &OptimizedFile{
		path: filePath,
		fd:   fd,
		size: s.maxFileSize,
	}

	s.files.Store(fileName, optimizedFile)
	return optimizedFile, nil
}

// prepareAlignedData prepares data with proper alignment for O_DIRECT
func (s *OptimizedSSDStorage) prepareAlignedData(key string, value []byte) []byte {
	keyBytes := []byte(key)

	// Calculate required size with headers
	dataSize := 4 + 4 + 8 + 4 + len(keyBytes) + len(value)

	// Align to page boundary for O_DIRECT
	alignedSize := ((dataSize + s.pageSize - 1) / s.pageSize) * s.pageSize

	// Allocate aligned buffer
	buffer := s.allocateAlignedBuffer(alignedSize)

	offset := 0

	// Write headers using binary encoding
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
func (s *OptimizedSSDStorage) allocateAlignedBuffer(size int) []byte {
	// Allocate extra space for alignment
	buf := make([]byte, size+s.pageSize)

	// Calculate aligned address
	addr := uintptr(unsafe.Pointer(&buf[0]))
	aligned := (addr + uintptr(s.pageSize-1)) & ^uintptr(s.pageSize-1)
	offset := aligned - addr

	return buf[offset : offset+uintptr(size)]
}

// parseData parses data from aligned buffer
func (s *OptimizedSSDStorage) parseData(buffer []byte, expectedKey string) ([]byte, error) {
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
func (s *OptimizedSSDStorage) getFileName(key string) string {
	hash := uint32(0)
	for i := 0; i < len(key); i++ {
		hash = hash*31 + uint32(key[i])
	}
	return fmt.Sprintf("cache_%d.dat", hash%uint32(s.maxFileSize/int64(s.pageSize)))
}

// calculatePosition calculates the position in the file for a given key
func (s *OptimizedSSDStorage) calculatePosition(key string) int {
	hash := uint32(0)
	for i := 0; i < len(key); i++ {
		hash = hash*31 + uint32(key[i])
	}
	return int(hash%uint32(s.maxFileSize/int64(s.pageSize))) * s.pageSize
}

// Close closes the storage and releases resources
func (s *OptimizedSSDStorage) Close() error {
	close(s.stopChan)
	s.wg.Wait()

	// Close all files
	s.files.Range(func(key, value interface{}) bool {
		if file, ok := value.(*OptimizedFile); ok {
			syscall.Close(file.fd)
		}
		return true
	})

	return nil
}

// GetMetrics returns storage metrics
func (s *OptimizedSSDStorage) GetMetrics() *StorageMetrics {
	return s.metrics
}

// Sync synchronizes all cached writes to disk
func (s *OptimizedSSDStorage) Sync() error {
	s.files.Range(func(key, value interface{}) bool {
		if file, ok := value.(*OptimizedFile); ok {
			syscall.Fsync(file.fd)
		}
		return true
	})
	return nil
}
