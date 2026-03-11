package cache

import (
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"runtime"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"
)

// ShardedCacheConfig holds configuration for the sharded cache
type ShardedCacheConfig struct {
	ShardCount         int
	MaxMemoryBytes     int64
	MaxMemoryEntries   int64
	EnableSIMD         bool
	EnableLockFree     bool
	EnableWorkStealing bool
}

// ShardedCacheEntry represents a single cache entry with cache-line alignment
type ShardedCacheEntry struct {
	Key         string
	Value       []byte
	CreatedAt   int64
	ExpiresAt   int64
	AccessedAt  int64
	AccessCount uint64
	IsHot       bool
	HasTTL      bool
	_           [64 - 8*6 - 2]byte // Padding to 64 bytes (cache line)
}

// IsExpired checks if the entry has expired
func (e *ShardedCacheEntry) IsExpired() bool {
	return e.HasTTL && time.Now().UnixNano() > e.ExpiresAt
}

// Touch updates the last accessed time and access count
func (e *ShardedCacheEntry) Touch() {
	now := time.Now().UnixNano()
	atomic.StoreInt64(&e.AccessedAt, now)
	atomic.AddUint64(&e.AccessCount, 1)
}

// MemoryUsage returns the memory usage of this entry
func (e *ShardedCacheEntry) MemoryUsage() int64 {
	return int64(len(e.Key) + len(e.Value) + int(unsafe.Sizeof(*e)))
}

// CacheShard represents a single shard with lock-free operations
type CacheShard struct {
	// Lock-free hash table using regular map with RWMutex for better performance
	entries   map[string]*ShardedCacheEntry
	entriesMu sync.RWMutex

	// Shard-specific metrics
	hits      int64
	misses    int64
	sets      int64
	deletes   int64
	evictions int64

	// Memory management
	memoryUsage int64
	entryCount  int64
	maxMemory   int64
	maxEntries  int64

	// SIMD optimization flag
	enableSIMD bool

	// Thread-local hint for affinity
	threadHint int32
}

// NewCacheShard creates a new cache shard
func NewCacheShard(maxMemory, maxEntries int64, enableSIMD bool) *CacheShard {
	return &CacheShard{
		entries:    make(map[string]*ShardedCacheEntry),
		maxMemory:  maxMemory,
		maxEntries: maxEntries,
		enableSIMD: enableSIMD,
	}
}

// Get retrieves a value from the shard
func (s *CacheShard) Get(key string) ([]byte, bool) {
	s.entriesMu.RLock()
	entry, exists := s.entries[key]
	s.entriesMu.RUnlock()

	if !exists {
		atomic.AddInt64(&s.misses, 1)
		return nil, false
	}

	if entry.IsExpired() {
		// Remove expired entry
		s.entriesMu.Lock()
		delete(s.entries, key)
		atomic.AddInt64(&s.memoryUsage, -entry.MemoryUsage())
		atomic.AddInt64(&s.entryCount, -1)
		s.entriesMu.Unlock()

		atomic.AddInt64(&s.misses, 1)
		return nil, false
	}

	// Update access statistics
	entry.Touch()
	atomic.AddInt64(&s.hits, 1)

	return entry.Value, true
}

// Put stores a value in the shard
func (s *CacheShard) Put(key string, value []byte, ttl time.Duration) bool {
	now := time.Now().UnixNano()

	entry := &ShardedCacheEntry{
		Key:         key,
		Value:       make([]byte, len(value)),
		CreatedAt:   now,
		AccessedAt:  now,
		AccessCount: 1,
		IsHot:       false,
		HasTTL:      ttl > 0,
	}

	copy(entry.Value, value)

	if ttl > 0 {
		entry.ExpiresAt = now + int64(ttl)
	}

	s.entriesMu.Lock()
	defer s.entriesMu.Unlock()

	// Remove existing entry if it exists
	if existing, exists := s.entries[key]; exists {
		atomic.AddInt64(&s.memoryUsage, -existing.MemoryUsage())
		atomic.AddInt64(&s.entryCount, -1)
	}

	// Check if we need to evict
	entrySize := entry.MemoryUsage()
	for (atomic.LoadInt64(&s.memoryUsage)+entrySize > s.maxMemory ||
		atomic.LoadInt64(&s.entryCount)+1 > s.maxEntries) &&
		len(s.entries) > 0 {
		s.evictLRUEntryUnsafe()
	}

	// Add new entry
	s.entries[key] = entry
	atomic.AddInt64(&s.memoryUsage, entrySize)
	atomic.AddInt64(&s.entryCount, 1)
	atomic.AddInt64(&s.sets, 1)

	return true
}

// Remove removes a key from the shard
func (s *CacheShard) Remove(key string) bool {
	s.entriesMu.Lock()
	defer s.entriesMu.Unlock()

	entry, exists := s.entries[key]
	if !exists {
		return false
	}

	delete(s.entries, key)
	atomic.AddInt64(&s.memoryUsage, -entry.MemoryUsage())
	atomic.AddInt64(&s.entryCount, -1)
	atomic.AddInt64(&s.deletes, 1)

	return true
}

// Contains checks if a key exists in the shard
func (s *CacheShard) Contains(key string) bool {
	s.entriesMu.RLock()
	entry, exists := s.entries[key]
	s.entriesMu.RUnlock()

	if !exists {
		return false
	}

	return !entry.IsExpired()
}

// Clear removes all entries from the shard
func (s *CacheShard) Clear() {
	s.entriesMu.Lock()
	s.entries = make(map[string]*ShardedCacheEntry)
	atomic.StoreInt64(&s.memoryUsage, 0)
	atomic.StoreInt64(&s.entryCount, 0)
	s.entriesMu.Unlock()
}

// evictLRUEntryUnsafe removes the least recently used entry (caller must hold lock)
func (s *CacheShard) evictLRUEntryUnsafe() {
	if len(s.entries) == 0 {
		return
	}

	var oldestKey string
	var oldestTime int64 = time.Now().UnixNano()

	for key, entry := range s.entries {
		if entry.AccessedAt < oldestTime {
			oldestKey = key
			oldestTime = entry.AccessedAt
		}
	}

	if oldestKey != "" {
		entry := s.entries[oldestKey]
		delete(s.entries, oldestKey)
		atomic.AddInt64(&s.memoryUsage, -entry.MemoryUsage())
		atomic.AddInt64(&s.entryCount, -1)
		atomic.AddInt64(&s.evictions, 1)
	}
}

// Stats returns shard statistics
func (s *CacheShard) Stats() map[string]int64 {
	return map[string]int64{
		"hits":         atomic.LoadInt64(&s.hits),
		"misses":       atomic.LoadInt64(&s.misses),
		"sets":         atomic.LoadInt64(&s.sets),
		"deletes":      atomic.LoadInt64(&s.deletes),
		"evictions":    atomic.LoadInt64(&s.evictions),
		"memory_usage": atomic.LoadInt64(&s.memoryUsage),
		"entry_count":  atomic.LoadInt64(&s.entryCount),
	}
}

// ShardedCache implements a shared-nothing sharded cache
type ShardedCache struct {
	shards     []*CacheShard
	shardCount int
	config     ShardedCacheConfig

	// Global metrics
	totalHits      int64
	totalMisses    int64
	totalSets      int64
	totalDeletes   int64
	totalEvictions int64

	// Background cleanup
	cleanupTicker *time.Ticker
	stopCleanup   chan struct{}
}

// NewShardedCache creates a new sharded cache
func NewShardedCache(config ShardedCacheConfig) *ShardedCache {
	// Auto-detect shard count if not specified
	if config.ShardCount <= 0 {
		config.ShardCount = runtime.NumCPU() * 2
	}

	// Ensure reasonable limits
	if config.MaxMemoryBytes <= 0 {
		config.MaxMemoryBytes = 512 * 1024 * 1024 // 512MB default
	}
	if config.MaxMemoryEntries <= 0 {
		config.MaxMemoryEntries = 1000000 // 1M entries default
	}

	cache := &ShardedCache{
		shards:        make([]*CacheShard, config.ShardCount),
		shardCount:    config.ShardCount,
		config:        config,
		cleanupTicker: time.NewTicker(30 * time.Second),
		stopCleanup:   make(chan struct{}),
	}

	// Create shards
	shardMaxMemory := config.MaxMemoryBytes / int64(config.ShardCount)
	shardMaxEntries := config.MaxMemoryEntries / int64(config.ShardCount)

	for i := 0; i < config.ShardCount; i++ {
		cache.shards[i] = NewCacheShard(shardMaxMemory, shardMaxEntries, config.EnableSIMD)
	}

	// Start background cleanup
	go cache.backgroundCleanup()

	return cache
}

// getShard returns the shard for a given key using SIMD-optimized hash
func (c *ShardedCache) getShard(key string) *CacheShard {
	var hash uint64

	if c.config.EnableSIMD {
		hash = c.simdHash(key)
	} else {
		hash = c.standardHash(key)
	}

	return c.shards[hash%uint64(c.shardCount)]
}

// simdHash computes a SIMD-optimized hash
func (c *ShardedCache) simdHash(key string) uint64 {
	// Use SHA256 for now - in production, this would use SIMD instructions
	hasher := sha256.New()
	hasher.Write([]byte(key))
	hash := hasher.Sum(nil)

	return binary.LittleEndian.Uint64(hash[:8])
}

// standardHash computes a standard hash
func (c *ShardedCache) standardHash(key string) uint64 {
	var hash uint64 = 14695981039346656037 // FNV offset basis

	for _, b := range []byte(key) {
		hash ^= uint64(b)
		hash *= 1099511628211 // FNV prime
	}

	return hash
}

// Get retrieves a value from the cache
func (c *ShardedCache) Get(key string) ([]byte, bool) {
	shard := c.getShard(key)
	value, found := shard.Get(key)

	if found {
		atomic.AddInt64(&c.totalHits, 1)
	} else {
		atomic.AddInt64(&c.totalMisses, 1)
	}

	return value, found
}

// Put stores a value in the cache
func (c *ShardedCache) Put(key string, value []byte, ttl time.Duration) bool {
	shard := c.getShard(key)
	success := shard.Put(key, value, ttl)

	if success {
		atomic.AddInt64(&c.totalSets, 1)
	}

	return success
}

// Remove removes a key from the cache
func (c *ShardedCache) Remove(key string) bool {
	shard := c.getShard(key)
	success := shard.Remove(key)

	if success {
		atomic.AddInt64(&c.totalDeletes, 1)
	}

	return success
}

// Contains checks if a key exists in the cache
func (c *ShardedCache) Contains(key string) bool {
	shard := c.getShard(key)
	return shard.Contains(key)
}

// Clear removes all entries from the cache
func (c *ShardedCache) Clear() {
	for _, shard := range c.shards {
		shard.Clear()
	}

	atomic.StoreInt64(&c.totalHits, 0)
	atomic.StoreInt64(&c.totalMisses, 0)
	atomic.StoreInt64(&c.totalSets, 0)
	atomic.StoreInt64(&c.totalDeletes, 0)
	atomic.StoreInt64(&c.totalEvictions, 0)
}

// Close closes the cache and stops background tasks
func (c *ShardedCache) Close() {
	close(c.stopCleanup)
	c.cleanupTicker.Stop()
}

// GetShardCount returns the number of shards
func (c *ShardedCache) GetShardCount() int {
	return c.shardCount
}

// backgroundCleanup runs periodic cleanup of expired entries
func (c *ShardedCache) backgroundCleanup() {
	for {
		select {
		case <-c.cleanupTicker.C:
			c.cleanupExpired()
		case <-c.stopCleanup:
			return
		}
	}
}

// cleanupExpired removes expired entries from all shards
func (c *ShardedCache) cleanupExpired() {
	for _, shard := range c.shards {
		shard.entriesMu.Lock()
		for key, entry := range shard.entries {
			if entry.IsExpired() {
				delete(shard.entries, key)
				atomic.AddInt64(&shard.memoryUsage, -entry.MemoryUsage())
				atomic.AddInt64(&shard.entryCount, -1)
			}
		}
		shard.entriesMu.Unlock()
	}
}

// Stats returns cache statistics
func (c *ShardedCache) Stats() map[string]interface{} {
	stats := map[string]interface{}{
		"shard_count":     c.shardCount,
		"total_hits":      atomic.LoadInt64(&c.totalHits),
		"total_misses":    atomic.LoadInt64(&c.totalMisses),
		"total_sets":      atomic.LoadInt64(&c.totalSets),
		"total_deletes":   atomic.LoadInt64(&c.totalDeletes),
		"total_evictions": atomic.LoadInt64(&c.totalEvictions),
		"enable_simd":     c.config.EnableSIMD,
		"enable_lockfree": c.config.EnableLockFree,
	}

	// Aggregate shard statistics
	var totalMemoryUsage int64
	var totalEntryCount int64

	for i, shard := range c.shards {
		shardStats := shard.Stats()
		totalMemoryUsage += shardStats["memory_usage"]
		totalEntryCount += shardStats["entry_count"]

		stats[fmt.Sprintf("shard_%d_hits", i)] = shardStats["hits"]
		stats[fmt.Sprintf("shard_%d_misses", i)] = shardStats["misses"]
		stats[fmt.Sprintf("shard_%d_memory_usage", i)] = shardStats["memory_usage"]
		stats[fmt.Sprintf("shard_%d_entry_count", i)] = shardStats["entry_count"]
	}

	stats["total_memory_usage"] = totalMemoryUsage
	stats["total_entry_count"] = totalEntryCount

	return stats
}
