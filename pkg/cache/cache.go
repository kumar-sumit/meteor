package cache

import (
	"context"
	"errors"
	"time"
)

// Common errors
var (
	ErrKeyNotFound = errors.New("key not found")
)

// BatchOperation represents a batched cache operation
type BatchOperation struct {
	Type   string // "GET", "PUT", "REMOVE"
	Key    string
	Value  []byte
	TTL    time.Duration
	Result chan BatchResult
}

// BatchResult represents the result of a batch operation
type BatchResult struct {
	Value []byte
	Error error
	Found bool
}

// Cache defines the interface for the distributed cache
type Cache interface {
	// Get retrieves a value from the cache
	Get(ctx context.Context, key string) ([]byte, error)

	// Put stores a value in the cache with optional TTL
	Put(ctx context.Context, key string, value []byte, ttl time.Duration) error

	// Remove deletes a value from the cache
	Remove(ctx context.Context, key string) error

	// Contains checks if a key exists in the cache
	Contains(ctx context.Context, key string) (bool, error)

	// Clear removes all entries from the cache
	Clear(ctx context.Context) error

	// Batch operations for improved performance
	BatchGet(ctx context.Context, keys []string) (map[string][]byte, error)
	BatchPut(ctx context.Context, entries map[string][]byte, ttl time.Duration) error
	BatchRemove(ctx context.Context, keys []string) error

	// Process batched operations
	ProcessBatch(ctx context.Context, operations []BatchOperation) error

	// Close shuts down the cache and releases resources
	Close() error
}

// Config holds the configuration for the cache
type Config struct {
	// BaseDir is the directory where cache files will be stored
	BaseDir string

	// MaxMemoryEntries is the maximum number of entries to keep in memory
	MaxMemoryEntries int

	// EntryTTL is the time-to-live for cache entries
	EntryTTL time.Duration

	// PageSize is the size of each storage page in bytes
	PageSize int

	// MaxFileSize is the maximum size of each cache file in bytes
	MaxFileSize int64
}

// DefaultConfig returns a default configuration for the cache
func DefaultConfig() *Config {
	return &Config{
		BaseDir:          "/tmp/meteor-cache",
		MaxMemoryEntries: 1000,
		EntryTTL:         time.Hour,
		PageSize:         4096,
		MaxFileSize:      1024 * 1024 * 1024, // 1GB
	}
}
