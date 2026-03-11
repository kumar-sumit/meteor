package cache

import (
	"context"
	"sync"
	"time"

	"github.com/kumar-sumit/meteor/pkg/storage"
)

// OptimizedSSDCache implements the Cache interface using optimized SSD storage
type OptimizedSSDCache struct {
	storage       *storage.OptimizedSSDStorage
	memoryCache   sync.Map
	maxEntries    int
	entryTTL      time.Duration
	cleanupTicker *time.Ticker
	done          chan struct{}
	wg            sync.WaitGroup
	metrics       *CacheMetrics
}

// CacheMetrics tracks cache performance metrics
type CacheMetrics struct {
	Hits          *storage.Counter
	Misses        *storage.Counter
	Evictions     *storage.Counter
	MemoryEntries *storage.Gauge
	GetLatency    *storage.LatencyHistogram
	PutLatency    *storage.LatencyHistogram
	RemoveLatency *storage.LatencyHistogram
}

// NewOptimizedSSDCache creates a new optimized SSD cache instance
func NewOptimizedSSDCache(config *Config) (*OptimizedSSDCache, error) {
	if config == nil {
		config = DefaultConfig()
	}

	optimizedStorage, err := storage.NewOptimizedSSDStorage(
		config.BaseDir,
		config.PageSize,
		config.MaxFileSize,
	)
	if err != nil {
		return nil, err
	}

	cache := &OptimizedSSDCache{
		storage:       optimizedStorage,
		maxEntries:    config.MaxMemoryEntries,
		entryTTL:      config.EntryTTL,
		cleanupTicker: time.NewTicker(time.Minute),
		done:          make(chan struct{}),
		metrics:       newCacheMetrics(),
	}

	cache.wg.Add(1)
	go cache.cleanupLoop()

	return cache, nil
}

// newCacheMetrics creates a new cache metrics instance
func newCacheMetrics() *CacheMetrics {
	return &CacheMetrics{
		Hits:          storage.NewCounter(),
		Misses:        storage.NewCounter(),
		Evictions:     storage.NewCounter(),
		MemoryEntries: storage.NewGauge(),
		GetLatency:    storage.NewLatencyHistogram(),
		PutLatency:    storage.NewLatencyHistogram(),
		RemoveLatency: storage.NewLatencyHistogram(),
	}
}

// cleanupLoop periodically removes expired entries from the memory cache
func (c *OptimizedSSDCache) cleanupLoop() {
	defer c.wg.Done()
	defer c.cleanupTicker.Stop()

	for {
		select {
		case <-c.cleanupTicker.C:
			c.cleanupExpiredEntries()
		case <-c.done:
			return
		}
	}
}

// cleanupExpiredEntries removes expired entries from memory cache
func (c *OptimizedSSDCache) cleanupExpiredEntries() {
	now := time.Now()
	var expiredKeys []string

	c.memoryCache.Range(func(key, value interface{}) bool {
		if entry, ok := value.(*CacheEntry); ok {
			if now.After(entry.expiryTime) {
				expiredKeys = append(expiredKeys, key.(string))
			}
		}
		return true
	})

	for _, key := range expiredKeys {
		c.memoryCache.Delete(key)
	}

	c.updateMemoryEntriesMetric()
}

// updateMemoryEntriesMetric updates the memory entries gauge
func (c *OptimizedSSDCache) updateMemoryEntriesMetric() {
	count := int64(0)
	c.memoryCache.Range(func(key, value interface{}) bool {
		count++
		return true
	})
	c.metrics.MemoryEntries.Set(float64(count))
}

// Get retrieves a value from the cache
func (c *OptimizedSSDCache) Get(ctx context.Context, key string) ([]byte, error) {
	start := time.Now()
	defer func() {
		c.metrics.GetLatency.Observe(time.Since(start))
	}()

	// Try memory cache first
	if value, ok := c.memoryCache.Load(key); ok {
		if entry, ok := value.(*CacheEntry); ok {
			if time.Now().Before(entry.expiryTime) {
				c.metrics.Hits.Inc()
				return entry.value, nil
			}
			c.memoryCache.Delete(key)
		}
	}

	// Try optimized SSD storage
	value, err := c.storage.ReadAsync(key)
	if err != nil {
		c.metrics.Misses.Inc()
		return nil, err
	}

	if value != nil {
		c.metrics.Hits.Inc()
		// Update memory cache
		c.updateMemoryCache(key, value)
		return value, nil
	}

	c.metrics.Misses.Inc()
	return nil, nil
}

// Put stores a value in the cache
func (c *OptimizedSSDCache) Put(ctx context.Context, key string, value []byte) error {
	start := time.Now()
	defer func() {
		c.metrics.PutLatency.Observe(time.Since(start))
	}()

	// Write to optimized SSD storage asynchronously
	if err := c.storage.WriteAsync(key, value); err != nil {
		return err
	}

	// Update memory cache
	c.updateMemoryCache(key, value)
	return nil
}

// updateMemoryCache updates the memory cache with LRU eviction
func (c *OptimizedSSDCache) updateMemoryCache(key string, value []byte) {
	// Count current entries
	entryCount := 0
	c.memoryCache.Range(func(k, v interface{}) bool {
		entryCount++
		return true
	})

	// If memory cache is full, remove oldest entry
	if entryCount >= c.maxEntries {
		c.evictOldestEntry()
	}

	// Add new entry
	entry := &CacheEntry{
		value:      value,
		expiryTime: time.Now().Add(c.entryTTL),
	}
	c.memoryCache.Store(key, entry)
	c.updateMemoryEntriesMetric()
}

// evictOldestEntry removes the oldest entry from memory cache
func (c *OptimizedSSDCache) evictOldestEntry() {
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
		c.metrics.Evictions.Inc()
	}
}

// Remove deletes a value from the cache
func (c *OptimizedSSDCache) Remove(ctx context.Context, key string) error {
	start := time.Now()
	defer func() {
		c.metrics.RemoveLatency.Observe(time.Since(start))
	}()

	// Remove from memory cache
	c.memoryCache.Delete(key)
	c.updateMemoryEntriesMetric()

	// Note: We don't remove from SSD storage as it's append-only
	// The entry will be ignored due to TTL or overwritten on next write
	return nil
}

// Contains checks if a key exists in the cache
func (c *OptimizedSSDCache) Contains(ctx context.Context, key string) (bool, error) {
	// Check memory cache first
	if value, ok := c.memoryCache.Load(key); ok {
		if entry, ok := value.(*CacheEntry); ok {
			if time.Now().Before(entry.expiryTime) {
				return true, nil
			}
			c.memoryCache.Delete(key)
		}
	}

	// Check optimized SSD storage
	value, err := c.storage.ReadAsync(key)
	if err != nil {
		return false, err
	}

	return value != nil, nil
}

// Clear removes all entries from the cache
func (c *OptimizedSSDCache) Clear(ctx context.Context) error {
	// Clear memory cache
	c.memoryCache = sync.Map{}
	c.updateMemoryEntriesMetric()

	// Note: We don't clear SSD storage as it would require recreating files
	// Entries will expire naturally based on TTL
	return nil
}

// Close shuts down the cache and releases resources
func (c *OptimizedSSDCache) Close() error {
	close(c.done)
	c.wg.Wait()

	// Sync all pending writes
	if err := c.storage.Sync(); err != nil {
		return err
	}

	return c.storage.Close()
}

// GetMetrics returns cache metrics
func (c *OptimizedSSDCache) GetMetrics() *CacheMetrics {
	return c.metrics
}

// GetStorageMetrics returns storage metrics
func (c *OptimizedSSDCache) GetStorageMetrics() *storage.StorageMetrics {
	return c.storage.GetMetrics()
}

// GetHitRate calculates the cache hit rate
func (c *OptimizedSSDCache) GetHitRate() float64 {
	hits := c.metrics.Hits.Value()
	misses := c.metrics.Misses.Value()
	total := hits + misses

	if total == 0 {
		return 0.0
	}

	return float64(hits) / float64(total)
}
