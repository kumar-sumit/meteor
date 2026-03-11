package cache

import (
	"context"
	"time"
)

// Cache defines the interface for the distributed cache
type Cache interface {
	// Get retrieves a value from the cache
	Get(ctx context.Context, key string) ([]byte, error)
	
	// Put stores a value in the cache
	Put(ctx context.Context, key string, value []byte) error
	
	// Remove deletes a value from the cache
	Remove(ctx context.Context, key string) error
	
	// Contains checks if a key exists in the cache
	Contains(ctx context.Context, key string) (bool, error)
	
	// Clear removes all entries from the cache
	Clear(ctx context.Context) error
	
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

// DefaultConfig returns a Config with default values
func DefaultConfig() *Config {
	return &Config{
		BaseDir:          "/tmp/meteor-cache",
		MaxMemoryEntries: 1000,
		EntryTTL:         time.Hour,
		PageSize:         4096, // 4KB
		MaxFileSize:      1024 * 1024 * 1024, // 1GB
	}
} 