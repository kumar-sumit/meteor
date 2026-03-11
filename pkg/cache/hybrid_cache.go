package cache

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/kumar-sumit/meteor/pkg/storage"
)

// HybridCache implements a high-performance cache with optional SSD overflow
type HybridCache struct {
	// In-memory cache (L1)
	memoryCache map[string]*HybridCacheEntry
	memoryMu    sync.RWMutex

	// SSD cache (L2) - optional based on configuration
	ssdStorage *storage.OptimizedSSDStorage
	ssdEnabled bool

	// Configuration
	maxMemoryEntries   int
	maxMemoryBytes     int64
	currentMemoryBytes int64

	// LRU tracking for memory cache
	lruHead *HybridCacheEntry
	lruTail *HybridCacheEntry

	// Metrics
	memoryHits   int64
	memoryMisses int64
	ssdHits      int64
	ssdMisses    int64
	evictions    int64

	// Lifecycle
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup

	// Background processes
	evictionTicker *time.Ticker
	metricsTicker  *time.Ticker
}

// HybridCacheEntry represents a cache entry with LRU tracking
type HybridCacheEntry struct {
	key       string
	value     []byte
	timestamp time.Time
	ttl       time.Duration
	accessed  time.Time
	inMemory  bool
	size      int64

	// LRU linked list pointers
	prev *HybridCacheEntry
	next *HybridCacheEntry
}

// HybridCacheConfig configures the hybrid cache
type HybridCacheConfig struct {
	// Memory cache configuration
	MaxMemoryEntries int
	MaxMemoryBytes   int64

	// Tiered storage configuration
	TieredPrefix string // If empty, pure in-memory cache; if set, enables SSD tier

	// SSD cache configuration (used only when TieredPrefix is set)
	SSDPageSize    int
	SSDMaxFileSize int64

	// Performance tuning
	EvictionInterval time.Duration
	MetricsInterval  time.Duration

	// Default TTL
	DefaultTTL time.Duration
}

// DefaultHybridCacheConfig returns a default configuration for pure in-memory cache
func DefaultHybridCacheConfig() *HybridCacheConfig {
	return &HybridCacheConfig{
		MaxMemoryEntries: 100000,            // 100K entries in memory
		MaxMemoryBytes:   256 * 1024 * 1024, // 256MB memory limit
		TieredPrefix:     "",                // Pure in-memory by default
		SSDPageSize:      4096,
		SSDMaxFileSize:   2 * 1024 * 1024 * 1024, // 2GB per file
		EvictionInterval: time.Second * 30,
		MetricsInterval:  time.Second * 10,
		DefaultTTL:       time.Hour,
	}
}

// NewHybridCache creates a new hybrid cache instance
func NewHybridCache(config *HybridCacheConfig) (*HybridCache, error) {
	if config == nil {
		config = DefaultHybridCacheConfig()
	}

	ctx, cancel := context.WithCancel(context.Background())

	cache := &HybridCache{
		memoryCache:      make(map[string]*HybridCacheEntry),
		ssdEnabled:       config.TieredPrefix != "",
		maxMemoryEntries: config.MaxMemoryEntries,
		maxMemoryBytes:   config.MaxMemoryBytes,
		ctx:              ctx,
		cancel:           cancel,
		evictionTicker:   time.NewTicker(config.EvictionInterval),
		metricsTicker:    time.NewTicker(config.MetricsInterval),
	}

	// Create SSD storage backend only if TieredPrefix is configured
	if cache.ssdEnabled {
		ssdStorage, err := storage.NewOptimizedSSDStorage(
			config.TieredPrefix,
			config.SSDPageSize,
			config.SSDMaxFileSize,
		)
		if err != nil {
			cancel()
			return nil, fmt.Errorf("failed to create SSD storage: %w", err)
		}
		cache.ssdStorage = ssdStorage
	}

	// Initialize LRU list
	cache.lruHead = &HybridCacheEntry{}
	cache.lruTail = &HybridCacheEntry{}
	cache.lruHead.next = cache.lruTail
	cache.lruTail.prev = cache.lruHead

	// Start background processes
	backgroundWorkers := 2
	if cache.ssdEnabled {
		backgroundWorkers = 3
	}

	cache.wg.Add(backgroundWorkers)
	go cache.evictionWorker()
	go cache.metricsWorker()
	if cache.ssdEnabled {
		go cache.ssdWorker()
	}

	return cache, nil
}

// Get retrieves a value from the cache
func (c *HybridCache) Get(ctx context.Context, key string) ([]byte, error) {
	// Try memory cache first (L1)
	c.memoryMu.RLock()
	if entry, exists := c.memoryCache[key]; exists {
		if !c.isExpired(entry) {
			// Move to front of LRU
			c.moveToFront(entry)
			entry.accessed = time.Now()
			atomic.AddInt64(&c.memoryHits, 1)
			value := make([]byte, len(entry.value))
			copy(value, entry.value)
			c.memoryMu.RUnlock()
			return value, nil
		} else {
			// Entry expired, remove it
			c.memoryMu.RUnlock()
			c.memoryMu.Lock()
			c.removeFromMemory(key)
			c.memoryMu.Unlock()
			atomic.AddInt64(&c.memoryMisses, 1)
		}
	} else {
		c.memoryMu.RUnlock()
		atomic.AddInt64(&c.memoryMisses, 1)
	}

	// Try SSD cache (L2) only if enabled
	if c.ssdEnabled {
		value, err := c.ssdStorage.ReadAsync(key)
		if err != nil {
			atomic.AddInt64(&c.ssdMisses, 1)
			return nil, err
		}

		if value != nil {
			atomic.AddInt64(&c.ssdHits, 1)
			// Promote to memory cache
			c.promoteToMemory(key, value, time.Hour) // Default TTL
			return value, nil
		}

		atomic.AddInt64(&c.ssdMisses, 1)
	}

	return nil, nil
}

// Put stores a value in the cache
func (c *HybridCache) Put(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	if ttl <= 0 {
		ttl = time.Hour // Default TTL
	}

	// Try to store in memory first (this is the fast path)
	if c.canFitInMemory(key, value) {
		// Fast path: store directly in memory without SSD write
		c.promoteToMemory(key, value, ttl)
		return nil
	}

	// Slow path: memory is full, need to use SSD in hybrid mode
	if c.ssdEnabled {
		// Write to SSD for persistence since memory is full
		if err := c.ssdStorage.WriteAsync(key, value); err != nil {
			return fmt.Errorf("failed to write to SSD: %w", err)
		}
		// Still try to store in memory (may cause eviction)
		c.promoteToMemory(key, value, ttl)
	} else {
		// Pure in-memory mode: just store in memory (may cause eviction)
		c.promoteToMemory(key, value, ttl)
	}

	return nil
}

// canFitInMemory checks if a key-value pair can fit in memory without eviction
func (c *HybridCache) canFitInMemory(key string, value []byte) bool {
	entrySize := int64(len(key) + len(value) + 128) // Approximate overhead

	c.memoryMu.RLock()
	currentEntries := len(c.memoryCache)
	c.memoryMu.RUnlock()

	currentMemoryBytes := atomic.LoadInt64(&c.currentMemoryBytes)

	// Check if we have space without eviction
	return currentEntries < c.maxMemoryEntries &&
		currentMemoryBytes+entrySize <= c.maxMemoryBytes
}

// Remove deletes a value from the cache
func (c *HybridCache) Remove(ctx context.Context, key string) error {
	// Remove from memory cache
	c.memoryMu.Lock()
	c.removeFromMemory(key)
	c.memoryMu.Unlock()

	// Note: We don't remove from SSD as it's append-only
	// The entry will be ignored due to TTL or overwritten

	return nil
}

// Contains checks if a key exists in the cache
func (c *HybridCache) Contains(ctx context.Context, key string) (bool, error) {
	// Check memory cache first
	c.memoryMu.RLock()
	if entry, exists := c.memoryCache[key]; exists {
		if !c.isExpired(entry) {
			c.memoryMu.RUnlock()
			return true, nil
		}
	}
	c.memoryMu.RUnlock()

	// Check SSD cache
	if c.ssdEnabled {
		value, err := c.ssdStorage.ReadAsync(key)
		if err != nil {
			return false, err
		}

		return value != nil, nil
	}

	return false, nil
}

// Clear removes all entries from the cache
func (c *HybridCache) Clear(ctx context.Context) error {
	c.memoryMu.Lock()
	defer c.memoryMu.Unlock()

	// Clear memory cache
	c.memoryCache = make(map[string]*HybridCacheEntry)
	c.lruHead.next = c.lruTail
	c.lruTail.prev = c.lruHead
	atomic.StoreInt64(&c.currentMemoryBytes, 0)

	// Note: We don't clear SSD storage as it would require file recreation

	return nil
}

// promoteToMemory promotes a key-value pair to memory cache
func (c *HybridCache) promoteToMemory(key string, value []byte, ttl time.Duration) {
	c.memoryMu.Lock()
	defer c.memoryMu.Unlock()

	entrySize := int64(len(key) + len(value) + 128) // Approximate overhead

	// Check if we need to evict entries
	for len(c.memoryCache) >= c.maxMemoryEntries ||
		atomic.LoadInt64(&c.currentMemoryBytes)+entrySize > c.maxMemoryBytes {

		if !c.evictLRUToSSD() {
			break // No more entries to evict
		}
	}

	// Create new entry
	entry := &HybridCacheEntry{
		key:       key,
		value:     make([]byte, len(value)),
		timestamp: time.Now(),
		ttl:       ttl,
		accessed:  time.Now(),
		inMemory:  true,
		size:      entrySize,
	}
	copy(entry.value, value)

	// Add to memory cache
	c.memoryCache[key] = entry
	c.addToFront(entry)
	atomic.AddInt64(&c.currentMemoryBytes, entrySize)
}

// evictLRUToSSD evicts the least recently used entry, optionally writing to SSD
func (c *HybridCache) evictLRUToSSD() bool {
	if c.lruTail.prev == c.lruHead {
		return false // No entries to evict
	}

	entry := c.lruTail.prev

	// Write to SSD before evicting from memory (hybrid mode only)
	if c.ssdEnabled {
		// Write evicted entry to SSD asynchronously
		go func(key string, value []byte) {
			if err := c.ssdStorage.WriteAsync(key, value); err != nil {
				// Log error but don't block eviction
				// In production, you might want to use a proper logger
				fmt.Printf("Failed to write evicted entry to SSD: %v\n", err)
			}
		}(entry.key, entry.value)
	}

	c.removeFromMemory(entry.key)
	atomic.AddInt64(&c.evictions, 1)
	return true
}

// evictLRU evicts the least recently used entry (backward compatibility)
func (c *HybridCache) evictLRU() bool {
	return c.evictLRUToSSD()
}

// removeFromMemory removes an entry from memory cache
func (c *HybridCache) removeFromMemory(key string) {
	if entry, exists := c.memoryCache[key]; exists {
		delete(c.memoryCache, key)
		c.removeFromLRU(entry)
		atomic.AddInt64(&c.currentMemoryBytes, -entry.size)
	}
}

// LRU list management
func (c *HybridCache) addToFront(entry *HybridCacheEntry) {
	entry.next = c.lruHead.next
	entry.prev = c.lruHead
	c.lruHead.next.prev = entry
	c.lruHead.next = entry
}

func (c *HybridCache) removeFromLRU(entry *HybridCacheEntry) {
	entry.prev.next = entry.next
	entry.next.prev = entry.prev
}

func (c *HybridCache) moveToFront(entry *HybridCacheEntry) {
	c.removeFromLRU(entry)
	c.addToFront(entry)
}

// isExpired checks if an entry is expired
func (c *HybridCache) isExpired(entry *HybridCacheEntry) bool {
	return time.Since(entry.timestamp) > entry.ttl
}

// Background workers
func (c *HybridCache) evictionWorker() {
	defer c.wg.Done()

	for {
		select {
		case <-c.ctx.Done():
			return
		case <-c.evictionTicker.C:
			c.performEviction()
		}
	}
}

func (c *HybridCache) metricsWorker() {
	defer c.wg.Done()

	for {
		select {
		case <-c.ctx.Done():
			return
		case <-c.metricsTicker.C:
			c.logMetrics()
		}
	}
}

func (c *HybridCache) ssdWorker() {
	defer c.wg.Done()

	// This worker can handle background SSD maintenance tasks
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-c.ctx.Done():
			return
		case <-ticker.C:
			// Perform SSD maintenance (e.g., compaction, cleanup)
			c.performSSDMaintenance()
		}
	}
}

// performEviction removes expired entries from memory cache
func (c *HybridCache) performEviction() {
	c.memoryMu.Lock()
	defer c.memoryMu.Unlock()

	now := time.Now()
	expiredKeys := make([]string, 0)

	for key, entry := range c.memoryCache {
		if now.Sub(entry.timestamp) > entry.ttl {
			expiredKeys = append(expiredKeys, key)
		}
	}

	for _, key := range expiredKeys {
		c.removeFromMemory(key)
	}
}

// performSSDMaintenance performs background SSD maintenance
func (c *HybridCache) performSSDMaintenance() {
	// Placeholder for SSD maintenance tasks
	// Could include compaction, cleanup, etc.
}

// logMetrics logs performance metrics
func (c *HybridCache) logMetrics() {
	memHits := atomic.LoadInt64(&c.memoryHits)
	memMisses := atomic.LoadInt64(&c.memoryMisses)
	ssdHits := atomic.LoadInt64(&c.ssdHits)
	ssdMisses := atomic.LoadInt64(&c.ssdMisses)
	evictions := atomic.LoadInt64(&c.evictions)

	memoryBytes := atomic.LoadInt64(&c.currentMemoryBytes)

	c.memoryMu.RLock()
	memoryEntries := len(c.memoryCache)
	c.memoryMu.RUnlock()

	fmt.Printf("HybridCache Metrics: MemHits=%d, MemMisses=%d, SSDHits=%d, SSDMisses=%d, Evictions=%d, MemEntries=%d, MemBytes=%d\n",
		memHits, memMisses, ssdHits, ssdMisses, evictions, memoryEntries, memoryBytes)
}

// GetStats returns cache statistics
func (c *HybridCache) GetStats() map[string]interface{} {
	c.memoryMu.RLock()
	memoryEntries := len(c.memoryCache)
	c.memoryMu.RUnlock()

	return map[string]interface{}{
		"memory_hits":      atomic.LoadInt64(&c.memoryHits),
		"memory_misses":    atomic.LoadInt64(&c.memoryMisses),
		"ssd_hits":         atomic.LoadInt64(&c.ssdHits),
		"ssd_misses":       atomic.LoadInt64(&c.ssdMisses),
		"evictions":        atomic.LoadInt64(&c.evictions),
		"memory_entries":   memoryEntries,
		"memory_bytes":     atomic.LoadInt64(&c.currentMemoryBytes),
		"max_memory_bytes": c.maxMemoryBytes,
		"memory_hit_rate":  float64(atomic.LoadInt64(&c.memoryHits)) / float64(atomic.LoadInt64(&c.memoryHits)+atomic.LoadInt64(&c.memoryMisses)+1),
		"ssd_hit_rate":     float64(atomic.LoadInt64(&c.ssdHits)) / float64(atomic.LoadInt64(&c.ssdHits)+atomic.LoadInt64(&c.ssdMisses)+1),
	}
}

// Close shuts down the cache and releases resources
func (c *HybridCache) Close() error {
	c.cancel()
	c.wg.Wait()

	c.evictionTicker.Stop()
	c.metricsTicker.Stop()

	if c.ssdEnabled {
		if err := c.ssdStorage.Close(); err != nil {
			return fmt.Errorf("failed to close SSD storage: %w", err)
		}
	}

	return nil
}

// Additional methods for batch operations
func (c *HybridCache) BatchGet(ctx context.Context, keys []string) (map[string][]byte, error) {
	results := make(map[string][]byte)

	for _, key := range keys {
		if value, err := c.Get(ctx, key); err == nil && value != nil {
			results[key] = value
		}
	}

	return results, nil
}

func (c *HybridCache) BatchPut(ctx context.Context, entries map[string][]byte, ttl time.Duration) error {
	for key, value := range entries {
		if err := c.Put(ctx, key, value, ttl); err != nil {
			return err
		}
	}
	return nil
}

func (c *HybridCache) BatchRemove(ctx context.Context, keys []string) error {
	for _, key := range keys {
		if err := c.Remove(ctx, key); err != nil {
			return err
		}
	}
	return nil
}
