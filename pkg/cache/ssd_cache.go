package cache

import (
	"context"
	"sync"
	"time"

	"github.com/kumar-sumit/meteor/pkg/storage"
)

// CacheEntry represents a single cache entry
type CacheEntry struct {
	value      []byte
	expiryTime time.Time
}

// SSDCache implements the Cache interface using SSD storage and memory cache
type SSDCache struct {
	storage       *storage.SSDStorage
	memoryCache   sync.Map
	maxEntries    int
	entryTTL      time.Duration
	cleanupTicker *time.Ticker
	done          chan struct{}
	wg            sync.WaitGroup
}

// NewSSDCache creates a new SSD cache instance
func NewSSDCache(config *Config) (*SSDCache, error) {
	if config == nil {
		config = DefaultConfig()
	}

	storage, err := storage.NewSSDStorage(config.BaseDir, config.PageSize, config.MaxFileSize)
	if err != nil {
		return nil, err
	}

	cache := &SSDCache{
		storage:       storage,
		maxEntries:    config.MaxMemoryEntries,
		entryTTL:      config.EntryTTL,
		cleanupTicker: time.NewTicker(time.Minute),
		done:          make(chan struct{}),
	}

	cache.wg.Add(1)
	go cache.cleanupLoop()

	return cache, nil
}

// cleanupLoop periodically removes expired entries from the memory cache
func (c *SSDCache) cleanupLoop() {
	defer c.wg.Done()
	defer c.cleanupTicker.Stop()

	for {
		select {
		case <-c.cleanupTicker.C:
			now := time.Now()
			c.memoryCache.Range(func(key, value interface{}) bool {
				if entry, ok := value.(*CacheEntry); ok {
					if now.After(entry.expiryTime) {
						c.memoryCache.Delete(key)
					}
				}
				return true
			})
		case <-c.done:
			return
		}
	}
}

// Get retrieves a value from the cache
func (c *SSDCache) Get(ctx context.Context, key string) ([]byte, error) {
	// Try memory cache first
	if value, ok := c.memoryCache.Load(key); ok {
		if entry, ok := value.(*CacheEntry); ok {
			if time.Now().Before(entry.expiryTime) {
				return entry.value, nil
			}
			c.memoryCache.Delete(key)
		}
	}

	// Try SSD storage
	value, err := c.storage.Read(key)
	if err != nil {
		return nil, err
	}

	if value != nil {
		// Update memory cache
		c.updateMemoryCache(key, value)
	}

	return value, nil
}

// Put stores a value in the cache
func (c *SSDCache) Put(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	// Write to SSD storage
	if err := c.storage.Write(key, value); err != nil {
		return err
	}

	// Update memory cache with specific TTL
	c.updateMemoryCacheWithTTL(key, value, ttl)
	return nil
}

// updateMemoryCache updates the memory cache with LRU eviction using default TTL
func (c *SSDCache) updateMemoryCache(key string, value []byte) {
	c.updateMemoryCacheWithTTL(key, value, c.entryTTL)
}

// updateMemoryCacheWithTTL updates the memory cache with LRU eviction using specific TTL
func (c *SSDCache) updateMemoryCacheWithTTL(key string, value []byte, ttl time.Duration) {
	// Count current entries
	entryCount := 0
	c.memoryCache.Range(func(k, v interface{}) bool {
		entryCount++
		return true
	})

	// If memory cache is full, remove oldest entry
	if entryCount >= c.maxEntries {
		var oldestKey interface{}
		var oldestTime time.Time
		first := true

		c.memoryCache.Range(func(k, v interface{}) bool {
			if entry, ok := v.(*CacheEntry); ok {
				if first || entry.expiryTime.Before(oldestTime) {
					oldestKey = k
					oldestTime = entry.expiryTime
					first = false
				}
			}
			return true
		})

		if oldestKey != nil {
			c.memoryCache.Delete(oldestKey)
		}
	}

	// Use default TTL if not specified
	if ttl <= 0 {
		ttl = c.entryTTL
	}

	// Add new entry
	entry := &CacheEntry{
		value:      value,
		expiryTime: time.Now().Add(ttl),
	}
	c.memoryCache.Store(key, entry)
}

// Remove deletes a value from the cache
func (c *SSDCache) Remove(ctx context.Context, key string) error {
	c.memoryCache.Delete(key)
	// TODO: Implement Remove in SSDStorage
	return nil
}

// Contains checks if a key exists in the cache
func (c *SSDCache) Contains(ctx context.Context, key string) (bool, error) {
	// Check memory cache first
	if value, ok := c.memoryCache.Load(key); ok {
		if entry, ok := value.(*CacheEntry); ok {
			if time.Now().Before(entry.expiryTime) {
				return true, nil
			}
			c.memoryCache.Delete(key)
		}
	}

	// Check SSD storage
	value, err := c.storage.Read(key)
	if err != nil {
		return false, err
	}

	return value != nil, nil
}

// Clear removes all entries from the cache
func (c *SSDCache) Clear(ctx context.Context) error {
	c.memoryCache = sync.Map{}
	// TODO: Implement Clear in SSDStorage
	return nil
}

// Close shuts down the cache and releases resources
func (c *SSDCache) Close() error {
	close(c.done)
	c.wg.Wait()
	return c.storage.Close()
}
