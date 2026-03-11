package storage

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"syscall"
)

// SSDStorage implements storage using memory-mapped files
type SSDStorage struct {
	baseDir     string
	pageSize    int
	maxFileSize int64
	files       sync.Map
	mu          sync.RWMutex
}

// NewSSDStorage creates a new SSD storage instance
func NewSSDStorage(baseDir string, pageSize int, maxFileSize int64) (*SSDStorage, error) {
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base directory: %w", err)
	}

	return &SSDStorage{
		baseDir:     baseDir,
		pageSize:    pageSize,
		maxFileSize: maxFileSize,
	}, nil
}

// getOrCreateFile returns a memory-mapped file for the given key
func (s *SSDStorage) getOrCreateFile(key string) (*os.File, []byte, error) {
	fileName := s.getFileName(key)

	// Try to get existing file
	if value, ok := s.files.Load(fileName); ok {
		if file, ok := value.(*os.File); ok {
			return file, nil, nil
		}
	}

	// Create new file
	s.mu.Lock()
	defer s.mu.Unlock()

	// Double-check after acquiring lock
	if value, ok := s.files.Load(fileName); ok {
		if file, ok := value.(*os.File); ok {
			return file, nil, nil
		}
	}

	filePath := filepath.Join(s.baseDir, fileName)
	file, err := os.OpenFile(filePath, os.O_RDWR|os.O_CREATE, 0644)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to open file: %w", err)
	}

	// Set file size
	if err := file.Truncate(s.maxFileSize); err != nil {
		file.Close()
		return nil, nil, fmt.Errorf("failed to set file size: %w", err)
	}

	// Memory map the file
	data, err := syscall.Mmap(
		int(file.Fd()),
		0,
		int(s.maxFileSize),
		syscall.PROT_READ|syscall.PROT_WRITE,
		syscall.MAP_SHARED,
	)
	if err != nil {
		file.Close()
		return nil, nil, fmt.Errorf("failed to memory map file: %w", err)
	}

	s.files.Store(fileName, file)
	return file, data, nil
}

// getFileName returns the file name for a given key
func (s *SSDStorage) getFileName(key string) string {
	hash := uint32(0)
	for i := 0; i < len(key); i++ {
		hash = hash*31 + uint32(key[i])
	}
	return fmt.Sprintf("cache_%d.dat", hash%uint32(s.maxFileSize/int64(s.pageSize)))
}

// Write writes data to the storage
func (s *SSDStorage) Write(key string, value []byte) error {
	_, data, err := s.getOrCreateFile(key)
	if err != nil {
		return err
	}

	position := s.calculatePosition(key)

	// Write key length (4 bytes)
	binary.LittleEndian.PutUint32(data[position:], uint32(len(key)))
	position += 4

	// Write value length (4 bytes)
	binary.LittleEndian.PutUint32(data[position:], uint32(len(value)))
	position += 4

	// Write key
	copy(data[position:], []byte(key))
	position += len(key)

	// Write value
	copy(data[position:], value)

	return nil
}

// Read reads data from the storage
func (s *SSDStorage) Read(key string) ([]byte, error) {
	_, data, err := s.getOrCreateFile(key)
	if err != nil {
		return nil, err
	}

	position := s.calculatePosition(key)

	// Read key length
	keyLen := binary.LittleEndian.Uint32(data[position:])
	position += 4

	// Read value length
	valueLen := binary.LittleEndian.Uint32(data[position:])
	position += 4

	// Read and verify key
	storedKey := string(data[position : position+int(keyLen)])
	if storedKey != key {
		return nil, nil // Key not found
	}
	position += int(keyLen)

	// Read value
	value := make([]byte, valueLen)
	copy(value, data[position:position+int(valueLen)])

	return value, nil
}

// calculatePosition calculates the position in the file for a given key
func (s *SSDStorage) calculatePosition(key string) int {
	hash := uint32(0)
	for i := 0; i < len(key); i++ {
		hash = hash*31 + uint32(key[i])
	}
	return int(hash%uint32(s.maxFileSize/int64(s.pageSize))) * s.pageSize
}

// Close closes all open files
func (s *SSDStorage) Close() error {
	var err error
	s.files.Range(func(key, value interface{}) bool {
		if file, ok := value.(*os.File); ok {
			if e := file.Close(); e != nil {
				err = e
				return false
			}
		}
		return true
	})
	return err
}
