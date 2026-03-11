package cache

import (
	"context"
	"sync"
	"time"
	"unsafe"
)

// ZeroCopyCache implements zero-copy cache operations
type ZeroCopyCache struct {
	*OptimizedSSDCache

	// Additional zero-copy optimizations
	keyPool   *sync.Pool
	valuePool *sync.Pool
}

// ByteKey represents a key as byte slice
type ByteKey []byte

// ByteValue represents a value as byte slice
type ByteValue []byte

// String converts ByteKey to string without allocation
func (k ByteKey) String() string {
	return *(*string)(unsafe.Pointer(&k))
}

// String converts ByteValue to string without allocation
func (v ByteValue) String() string {
	return *(*string)(unsafe.Pointer(&v))
}

// NewZeroCopyCache creates a new zero-copy cache
func NewZeroCopyCache(config *Config) (*ZeroCopyCache, error) {
	baseCache, err := NewOptimizedSSDCache(config)
	if err != nil {
		return nil, err
	}

	return &ZeroCopyCache{
		OptimizedSSDCache: baseCache,
		keyPool: &sync.Pool{
			New: func() interface{} {
				return make([]byte, 0, 64)
			},
		},
		valuePool: &sync.Pool{
			New: func() interface{} {
				return make([]byte, 0, 1024)
			},
		},
	}, nil
}

// GetBytes retrieves a value using byte key
func (c *ZeroCopyCache) GetBytes(ctx context.Context, key ByteKey) (ByteValue, error) {
	// Convert byte key to string for underlying cache
	keyStr := key.String()

	value, err := c.OptimizedSSDCache.Get(ctx, keyStr)
	if err != nil {
		return nil, err
	}

	// Return value as byte slice
	return ByteValue(value), nil
}

// PutBytes stores a value using byte key and value
func (c *ZeroCopyCache) PutBytes(ctx context.Context, key ByteKey, value ByteValue, ttl time.Duration) error {
	// Convert byte key to string for underlying cache
	keyStr := key.String()

	// Store byte value directly
	return c.OptimizedSSDCache.Put(ctx, keyStr, []byte(value), ttl)
}

// RemoveBytes removes a key using byte key
func (c *ZeroCopyCache) RemoveBytes(ctx context.Context, key ByteKey) error {
	keyStr := key.String()
	return c.OptimizedSSDCache.Remove(ctx, keyStr)
}

// ContainsBytes checks if key exists using byte key
func (c *ZeroCopyCache) ContainsBytes(ctx context.Context, key ByteKey) (bool, error) {
	keyStr := key.String()
	return c.OptimizedSSDCache.Contains(ctx, keyStr)
}

// BatchGetBytes retrieves multiple values using byte keys
func (c *ZeroCopyCache) BatchGetBytes(ctx context.Context, keys []ByteKey) (map[string]ByteValue, error) {
	// Convert byte keys to string keys
	stringKeys := make([]string, len(keys))
	for i, key := range keys {
		stringKeys[i] = key.String()
	}

	// Get from underlying cache
	results, err := c.OptimizedSSDCache.BatchGet(ctx, stringKeys)
	if err != nil {
		return nil, err
	}

	// Convert results to byte values
	byteResults := make(map[string]ByteValue, len(results))
	for key, value := range results {
		byteResults[key] = ByteValue(value)
	}

	return byteResults, nil
}

// BatchPutBytes stores multiple values using byte keys and values
func (c *ZeroCopyCache) BatchPutBytes(ctx context.Context, entries map[string]ByteValue, ttl time.Duration) error {
	// Convert byte values to byte slices
	byteEntries := make(map[string][]byte, len(entries))
	for key, value := range entries {
		byteEntries[key] = []byte(value)
	}

	return c.OptimizedSSDCache.BatchPut(ctx, byteEntries, ttl)
}

// GetKeyBuffer gets a key buffer from the pool
func (c *ZeroCopyCache) GetKeyBuffer() []byte {
	return c.keyPool.Get().([]byte)[:0]
}

// PutKeyBuffer returns a key buffer to the pool
func (c *ZeroCopyCache) PutKeyBuffer(buf []byte) {
	if cap(buf) <= 1024 { // Don't pool overly large buffers
		c.keyPool.Put(buf)
	}
}

// GetValueBuffer gets a value buffer from the pool
func (c *ZeroCopyCache) GetValueBuffer() []byte {
	return c.valuePool.Get().([]byte)[:0]
}

// PutValueBuffer returns a value buffer to the pool
func (c *ZeroCopyCache) PutValueBuffer(buf []byte) {
	if cap(buf) <= 8192 { // Don't pool overly large buffers
		c.valuePool.Put(buf)
	}
}

// OptimizedCacheHandler provides optimized command handlers
type OptimizedCacheHandler struct {
	cache *ZeroCopyCache
}

// NewOptimizedCacheHandler creates a new optimized cache handler
func NewOptimizedCacheHandler(cache *ZeroCopyCache) *OptimizedCacheHandler {
	return &OptimizedCacheHandler{
		cache: cache,
	}
}

// HandleGetCommand handles GET command with zero-copy optimization
func (h *OptimizedCacheHandler) HandleGetCommand(ctx context.Context, key []byte) ([]byte, error) {
	value, err := h.cache.GetBytes(ctx, ByteKey(key))
	if err != nil {
		return nil, err
	}
	return []byte(value), nil
}

// HandleSetCommand handles SET command with zero-copy optimization
func (h *OptimizedCacheHandler) HandleSetCommand(ctx context.Context, key, value []byte, ttl time.Duration) error {
	return h.cache.PutBytes(ctx, ByteKey(key), ByteValue(value), ttl)
}

// HandleDelCommand handles DEL command with zero-copy optimization
func (h *OptimizedCacheHandler) HandleDelCommand(ctx context.Context, key []byte) error {
	return h.cache.RemoveBytes(ctx, ByteKey(key))
}

// HandleExistsCommand handles EXISTS command with zero-copy optimization
func (h *OptimizedCacheHandler) HandleExistsCommand(ctx context.Context, key []byte) (bool, error) {
	return h.cache.ContainsBytes(ctx, ByteKey(key))
}

// MemoryPool provides memory pool optimization
type MemoryPool struct {
	small  *sync.Pool // For small allocations (< 1KB)
	medium *sync.Pool // For medium allocations (1KB - 8KB)
	large  *sync.Pool // For large allocations (8KB - 64KB)
}

// NewMemoryPool creates a new memory pool
func NewMemoryPool() *MemoryPool {
	return &MemoryPool{
		small: &sync.Pool{
			New: func() interface{} {
				return make([]byte, 0, 1024)
			},
		},
		medium: &sync.Pool{
			New: func() interface{} {
				return make([]byte, 0, 8*1024)
			},
		},
		large: &sync.Pool{
			New: func() interface{} {
				return make([]byte, 0, 64*1024)
			},
		},
	}
}

// Get gets a buffer from the appropriate pool
func (p *MemoryPool) Get(size int) []byte {
	switch {
	case size <= 1024:
		buf := p.small.Get().([]byte)
		if cap(buf) >= size {
			return buf[:size]
		}
		return make([]byte, size)
	case size <= 8*1024:
		buf := p.medium.Get().([]byte)
		if cap(buf) >= size {
			return buf[:size]
		}
		return make([]byte, size)
	case size <= 64*1024:
		buf := p.large.Get().([]byte)
		if cap(buf) >= size {
			return buf[:size]
		}
		return make([]byte, size)
	default:
		return make([]byte, size)
	}
}

// Put returns a buffer to the appropriate pool
func (p *MemoryPool) Put(buf []byte) {
	if buf == nil {
		return
	}

	switch {
	case cap(buf) <= 1024:
		p.small.Put(buf[:0])
	case cap(buf) <= 8*1024:
		p.medium.Put(buf[:0])
	case cap(buf) <= 64*1024:
		p.large.Put(buf[:0])
	}
}

// Global memory pool instance
var GlobalMemoryPool = NewMemoryPool()

// FastStringToBytes converts string to bytes without allocation
func FastStringToBytes(s string) []byte {
	return *(*[]byte)(unsafe.Pointer(&s))
}

// FastBytesToString converts bytes to string without allocation
func FastBytesToString(b []byte) string {
	return *(*string)(unsafe.Pointer(&b))
}
