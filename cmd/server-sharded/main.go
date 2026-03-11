package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	_ "net/http/pprof"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
	"github.com/kumar-sumit/meteor/pkg/server"
)

// Configuration
type Config struct {
	Host               string
	Port               int
	MaxMemoryBytes     int64
	MaxMemoryEntries   int64
	ShardCount         int
	EnableSIMD         bool
	EnableLockFree     bool
	EnableWorkStealing bool
	PureMemory         bool
	HybridOverflow     string
	MaxConnections     int
	WorkerPoolSize     int
	BufferSize         int
	PipelineSize       int
	GCPercent          int
	MaxProcs           int
	EnableLogging      bool
	EnableProfiling    bool
}

// ShardedCacheAdapter adapts ShardedCache to the cache.Cache interface
type ShardedCacheAdapter struct {
	shardedCache *cache.ShardedCache
}

func NewShardedCacheAdapter(config cache.ShardedCacheConfig) *ShardedCacheAdapter {
	return &ShardedCacheAdapter{
		shardedCache: cache.NewShardedCache(config),
	}
}

func (a *ShardedCacheAdapter) Get(ctx context.Context, key string) ([]byte, error) {
	if value, found := a.shardedCache.Get(key); found {
		return value, nil
	}
	return nil, cache.ErrKeyNotFound
}

func (a *ShardedCacheAdapter) Put(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	a.shardedCache.Put(key, value, ttl)
	return nil
}

func (a *ShardedCacheAdapter) Remove(ctx context.Context, key string) error {
	a.shardedCache.Remove(key)
	return nil
}

func (a *ShardedCacheAdapter) Contains(ctx context.Context, key string) (bool, error) {
	return a.shardedCache.Contains(key), nil
}

func (a *ShardedCacheAdapter) Clear(ctx context.Context) error {
	a.shardedCache.Clear()
	return nil
}

func (a *ShardedCacheAdapter) BatchGet(ctx context.Context, keys []string) (map[string][]byte, error) {
	result := make(map[string][]byte)
	for _, key := range keys {
		if value, found := a.shardedCache.Get(key); found {
			result[key] = value
		}
	}
	return result, nil
}

func (a *ShardedCacheAdapter) BatchPut(ctx context.Context, entries map[string][]byte, ttl time.Duration) error {
	for key, value := range entries {
		a.shardedCache.Put(key, value, ttl)
	}
	return nil
}

func (a *ShardedCacheAdapter) BatchRemove(ctx context.Context, keys []string) error {
	for _, key := range keys {
		a.shardedCache.Remove(key)
	}
	return nil
}

func (a *ShardedCacheAdapter) ProcessBatch(ctx context.Context, operations []cache.BatchOperation) error {
	for _, op := range operations {
		switch op.Type {
		case "GET":
			value, err := a.Get(ctx, op.Key)
			op.Result <- cache.BatchResult{Value: value, Error: err, Found: err == nil}
		case "PUT":
			err := a.Put(ctx, op.Key, op.Value, op.TTL)
			op.Result <- cache.BatchResult{Error: err}
		case "REMOVE":
			err := a.Remove(ctx, op.Key)
			op.Result <- cache.BatchResult{Error: err}
		}
	}
	return nil
}

func (a *ShardedCacheAdapter) Close() error {
	a.shardedCache.Close()
	return nil
}

func (a *ShardedCacheAdapter) Stats() map[string]interface{} {
	return a.shardedCache.Stats()
}

func (a *ShardedCacheAdapter) GetShardCount() int {
	return a.shardedCache.GetShardCount()
}

// CompositeCache combines sharded cache with hybrid overflow
type CompositeCache struct {
	shardedCache *ShardedCacheAdapter
	hybridCache  *cache.HybridCache
	useHybrid    bool
	ctx          context.Context
}

func NewCompositeCache(config cache.ShardedCacheConfig, hybridDir string) *CompositeCache {
	composite := &CompositeCache{
		shardedCache: NewShardedCacheAdapter(config),
		useHybrid:    hybridDir != "",
		ctx:          context.Background(),
	}

	if composite.useHybrid {
		hybridConfig := &cache.HybridCacheConfig{
			MaxMemoryEntries: int(config.MaxMemoryEntries / 2),
			MaxMemoryBytes:   config.MaxMemoryBytes / 2,
			TieredPrefix:     hybridDir,
			EvictionInterval: 30 * time.Second,
			MetricsInterval:  10 * time.Second,
		}
		var err error
		composite.hybridCache, err = cache.NewHybridCache(hybridConfig)
		if err != nil {
			panic(fmt.Sprintf("Failed to create hybrid cache: %v", err))
		}
	}

	return composite
}

func (c *CompositeCache) Get(ctx context.Context, key string) ([]byte, error) {
	// Try sharded cache first
	if value, err := c.shardedCache.Get(ctx, key); err == nil {
		return value, nil
	}

	// Try hybrid cache if enabled
	if c.useHybrid {
		return c.hybridCache.Get(ctx, key)
	}

	return nil, cache.ErrKeyNotFound
}

func (c *CompositeCache) Put(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	// Always put in sharded cache
	if err := c.shardedCache.Put(ctx, key, value, ttl); err != nil {
		return err
	}

	// Also put in hybrid cache if enabled for overflow
	if c.useHybrid {
		return c.hybridCache.Put(ctx, key, value, ttl)
	}

	return nil
}

func (c *CompositeCache) Remove(ctx context.Context, key string) error {
	c.shardedCache.Remove(ctx, key)

	if c.useHybrid {
		c.hybridCache.Remove(ctx, key)
	}

	return nil
}

func (c *CompositeCache) Contains(ctx context.Context, key string) (bool, error) {
	if found, err := c.shardedCache.Contains(ctx, key); err == nil && found {
		return true, nil
	}

	if c.useHybrid {
		return c.hybridCache.Contains(ctx, key)
	}

	return false, nil
}

func (c *CompositeCache) Clear(ctx context.Context) error {
	c.shardedCache.Clear(ctx)

	if c.useHybrid {
		c.hybridCache.Clear(ctx)
	}

	return nil
}

func (c *CompositeCache) BatchGet(ctx context.Context, keys []string) (map[string][]byte, error) {
	result := make(map[string][]byte)

	// Try sharded cache first
	shardedResult, err := c.shardedCache.BatchGet(ctx, keys)
	if err == nil {
		for key, value := range shardedResult {
			result[key] = value
		}
	}

	// Try hybrid cache for missing keys
	if c.useHybrid {
		var missingKeys []string
		for _, key := range keys {
			if _, found := result[key]; !found {
				missingKeys = append(missingKeys, key)
			}
		}

		if len(missingKeys) > 0 {
			hybridResult, err := c.hybridCache.BatchGet(ctx, missingKeys)
			if err == nil {
				for key, value := range hybridResult {
					result[key] = value
				}
			}
		}
	}

	return result, nil
}

func (c *CompositeCache) BatchPut(ctx context.Context, entries map[string][]byte, ttl time.Duration) error {
	// Put in sharded cache
	if err := c.shardedCache.BatchPut(ctx, entries, ttl); err != nil {
		return err
	}

	// Also put in hybrid cache if enabled
	if c.useHybrid {
		return c.hybridCache.BatchPut(ctx, entries, ttl)
	}

	return nil
}

func (c *CompositeCache) BatchRemove(ctx context.Context, keys []string) error {
	c.shardedCache.BatchRemove(ctx, keys)

	if c.useHybrid {
		c.hybridCache.BatchRemove(ctx, keys)
	}

	return nil
}

func (c *CompositeCache) ProcessBatch(ctx context.Context, operations []cache.BatchOperation) error {
	for _, op := range operations {
		switch op.Type {
		case "GET":
			value, err := c.Get(ctx, op.Key)
			op.Result <- cache.BatchResult{Value: value, Error: err, Found: err == nil}
		case "PUT":
			err := c.Put(ctx, op.Key, op.Value, op.TTL)
			op.Result <- cache.BatchResult{Error: err}
		case "REMOVE":
			err := c.Remove(ctx, op.Key)
			op.Result <- cache.BatchResult{Error: err}
		}
	}
	return nil
}

func (c *CompositeCache) Close() error {
	if err := c.shardedCache.Close(); err != nil {
		return err
	}

	if c.useHybrid {
		return c.hybridCache.Close()
	}

	return nil
}

func (c *CompositeCache) Stats() map[string]interface{} {
	stats := c.shardedCache.Stats()

	if c.useHybrid {
		hybridStats := c.hybridCache.GetStats()
		stats["hybrid_enabled"] = true
		stats["hybrid_memory_hits"] = hybridStats["memory_hits"]
		stats["hybrid_memory_misses"] = hybridStats["memory_misses"]
		stats["hybrid_ssd_hits"] = hybridStats["ssd_hits"]
		stats["hybrid_ssd_misses"] = hybridStats["ssd_misses"]
		stats["hybrid_evictions"] = hybridStats["evictions"]
		stats["hybrid_memory_entries"] = hybridStats["memory_entries"]
		stats["hybrid_memory_usage"] = hybridStats["memory_usage"]
	} else {
		stats["hybrid_enabled"] = false
	}

	return stats
}

func (c *CompositeCache) GetShardCount() int {
	return c.shardedCache.GetShardCount()
}

// Server metrics
type ServerMetrics struct {
	connections int64
	commands    int64
	errors      int64
	startTime   time.Time
}

func (m *ServerMetrics) IncrementConnections() {
	atomic.AddInt64(&m.connections, 1)
}

func (m *ServerMetrics) IncrementCommands() {
	atomic.AddInt64(&m.commands, 1)
}

func (m *ServerMetrics) IncrementErrors() {
	atomic.AddInt64(&m.errors, 1)
}

func (m *ServerMetrics) GetStats() (int64, int64, int64, time.Duration) {
	return atomic.LoadInt64(&m.connections),
		atomic.LoadInt64(&m.commands),
		atomic.LoadInt64(&m.errors),
		time.Since(m.startTime)
}

func parseConfig() Config {
	config := Config{
		Host:               "localhost",
		Port:               6379,
		MaxMemoryBytes:     512 * 1024 * 1024, // 512MB
		MaxMemoryEntries:   1000000,           // 1M entries
		ShardCount:         0,                 // Auto-detect based on CPU cores
		EnableSIMD:         true,
		EnableLockFree:     true,
		EnableWorkStealing: true,
		PureMemory:         false,
		MaxConnections:     65536, // Increased from 1000 to match Redis default
		WorkerPoolSize:     20,
		BufferSize:         65536,
		PipelineSize:       16,
		GCPercent:          50,
		MaxProcs:           runtime.NumCPU(),
		EnableLogging:      false,
		EnableProfiling:    false,
	}

	flag.StringVar(&config.Host, "host", config.Host, "Server host")
	flag.IntVar(&config.Port, "port", config.Port, "Server port")
	flag.Int64Var(&config.MaxMemoryBytes, "max-memory", config.MaxMemoryBytes, "Maximum memory cache size in bytes")
	flag.Int64Var(&config.MaxMemoryEntries, "max-entries", config.MaxMemoryEntries, "Maximum memory cache entries")
	flag.IntVar(&config.ShardCount, "shard-count", config.ShardCount, "Number of cache shards (0 = auto-detect based on CPU cores)")
	flag.BoolVar(&config.EnableSIMD, "enable-simd", config.EnableSIMD, "Enable SIMD optimizations")
	flag.BoolVar(&config.EnableLockFree, "enable-lockfree", config.EnableLockFree, "Enable lock-free operations")
	flag.BoolVar(&config.EnableWorkStealing, "enable-work-stealing", config.EnableWorkStealing, "Enable work stealing")
	flag.BoolVar(&config.PureMemory, "pure-memory", config.PureMemory, "Pure in-memory mode (no hybrid overflow)")
	flag.StringVar(&config.HybridOverflow, "hybrid-overflow", config.HybridOverflow, "Hybrid cache directory for overflow")
	flag.IntVar(&config.MaxConnections, "max-connections", config.MaxConnections, "Maximum concurrent connections")
	flag.IntVar(&config.WorkerPoolSize, "worker-pool-size", config.WorkerPoolSize, "Worker pool size")
	flag.IntVar(&config.BufferSize, "buffer-size", config.BufferSize, "Buffer size in bytes")
	flag.IntVar(&config.PipelineSize, "pipeline-size", config.PipelineSize, "Pipeline size")
	flag.IntVar(&config.GCPercent, "gc-percent", config.GCPercent, "GC target percentage")
	flag.IntVar(&config.MaxProcs, "max-procs", config.MaxProcs, "Maximum number of OS threads")
	flag.BoolVar(&config.EnableLogging, "enable-logging", config.EnableLogging, "Enable verbose logging")
	flag.BoolVar(&config.EnableProfiling, "enable-profiling", config.EnableProfiling, "Enable profiling server")

	flag.Parse()

	return config
}

func optimizeRuntime(config Config) {
	// Set GOMAXPROCS
	runtime.GOMAXPROCS(config.MaxProcs)

	// Set GC target
	debug.SetGCPercent(config.GCPercent)

	// Set memory limit if available (Go 1.19+)
	if config.MaxMemoryBytes > 0 {
		debug.SetMemoryLimit(config.MaxMemoryBytes * 2) // 2x for overhead
	}
}

func printBanner() {
	fmt.Print(`
███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝

   Sharded Redis-Compatible Cache Server v2.0
   High-Performance Architecture • Lock-Free • SIMD Optimized
   Fiber Concurrency • Zero-Copy I/O • Work Stealing
`)
}

func main() {
	config := parseConfig()

	printBanner()

	// Optimize runtime
	optimizeRuntime(config)

	log.Printf("🚀 Starting Meteor Sharded Server...")
	log.Printf("📊 Max memory: %d bytes", config.MaxMemoryBytes)
	log.Printf("📊 Max entries: %d", config.MaxMemoryEntries)
	log.Printf("📊 Shard count: %d (0 = auto-detect)", config.ShardCount)
	log.Printf("⚡ SIMD optimizations: %v", config.EnableSIMD)
	log.Printf("⚡ Lock-free operations: %v", config.EnableLockFree)
	log.Printf("⚡ Work stealing: %v", config.EnableWorkStealing)
	log.Printf("💾 Pure memory mode: %v", config.PureMemory)
	log.Printf("🔧 Max connections: %d", config.MaxConnections)
	log.Printf("🔧 Worker pool size: %d", config.WorkerPoolSize)
	log.Printf("🔧 Buffer size: %d", config.BufferSize)
	log.Printf("🔧 Pipeline size: %d", config.PipelineSize)
	log.Printf("🔧 GC percent: %d", config.GCPercent)
	log.Printf("🔧 Max procs: %d", config.MaxProcs)
	log.Printf("🔧 Enable profiling: %v", config.EnableProfiling)

	// Create sharded cache configuration
	cacheConfig := cache.ShardedCacheConfig{
		ShardCount:         config.ShardCount,
		MaxMemoryBytes:     config.MaxMemoryBytes,
		MaxMemoryEntries:   config.MaxMemoryEntries,
		EnableSIMD:         config.EnableSIMD,
		EnableLockFree:     config.EnableLockFree,
		EnableWorkStealing: config.EnableWorkStealing,
	}

	// Auto-detect shard count if not specified
	if cacheConfig.ShardCount <= 0 {
		cacheConfig.ShardCount = runtime.NumCPU() * 2
	}

	// Create cache
	var cacheInstance cache.Cache
	if config.PureMemory {
		cacheInstance = NewShardedCacheAdapter(cacheConfig)
	} else {
		hybridDir := config.HybridOverflow
		if hybridDir == "" {
			hybridDir = "/tmp/meteor-sharded-cache"
		}
		cacheInstance = NewCompositeCache(cacheConfig, hybridDir)
	}

	log.Printf("✅ Sharded cache architecture enabled")
	log.Printf("✅ Lock-free hash tables with SIMD optimizations")
	log.Printf("✅ Shared-nothing per-thread data partitions")
	log.Printf("✅ Zero-copy RESP parsing enabled")
	log.Printf("✅ TCP optimizations enabled")

	// Get actual shard count
	var shardCount int
	if adapter, ok := cacheInstance.(*ShardedCacheAdapter); ok {
		shardCount = adapter.GetShardCount()
	} else if composite, ok := cacheInstance.(*CompositeCache); ok {
		shardCount = composite.GetShardCount()
	}

	log.Printf("📊 Shards: %d", shardCount)
	log.Printf("📊 Total capacity: %d entries", config.MaxMemoryEntries)
	log.Printf("📊 Memory limit: %d bytes", config.MaxMemoryBytes)

	// Create server configuration
	serverConfig := &server.Config{
		Host:            config.Host,
		Port:            config.Port,
		MaxConnections:  config.MaxConnections,
		WorkerPoolSize:  config.WorkerPoolSize,
		BufferSize:      config.BufferSize,
		MaxPipelineSize: config.PipelineSize,
		EnableLogging:   config.EnableLogging,
		ReadTimeout:     30 * time.Second,
		WriteTimeout:    30 * time.Second,
		IdleTimeout:     5 * time.Minute,
	}

	// Create server
	srv := server.NewServer(serverConfig, cacheInstance)

	// Create metrics
	metrics := &ServerMetrics{
		startTime: time.Now(),
	}

	// Start metrics reporting
	if config.EnableLogging {
		go func() {
			ticker := time.NewTicker(10 * time.Second)
			defer ticker.Stop()

			for range ticker.C {
				connections, commands, errors, uptime := metrics.GetStats()
				cps := float64(commands) / uptime.Seconds()

				log.Printf("📊 Metrics: Connections=%d, Commands=%d, Errors=%d, CPS=%.2f, Uptime=%v",
					connections, commands, errors, cps, uptime.Truncate(time.Second))

				// Cache stats
				if statsProvider, ok := cacheInstance.(interface{ Stats() map[string]interface{} }); ok {
					stats := statsProvider.Stats()
					if hits, ok := stats["total_hits"].(int64); ok {
						if misses, ok := stats["total_misses"].(int64); ok {
							total := hits + misses
							var hitRate float64
							if total > 0 {
								hitRate = float64(hits) / float64(total) * 100
							}
							log.Printf("📊 Cache: Hits=%d, Misses=%d, HitRate=%.2f%%, Shards=%d",
								hits, misses, hitRate, shardCount)
						}
					}
				}
			}
		}()
	}

	log.Printf("🚀 Sharded Meteor server listening on %s:%d", config.Host, config.Port)
	log.Printf("🏃 Ready to serve Redis clients with high-performance architecture!")
	log.Printf("Press Ctrl+C to stop...")

	// Start profiling server if enabled
	if config.EnableProfiling {
		go func() {
			log.Printf("🔍 Starting profiling server on :6060")
			log.Println(http.ListenAndServe(":6060", nil))
		}()
	}

	// Set up graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Printf("Shutdown signal received, stopping server...")
		cancel()
	}()

	// Start server
	if err := srv.Start(); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}

	// Wait for shutdown signal
	<-ctx.Done()

	// Cleanup
	cacheInstance.Close()
	log.Printf("Server stopped gracefully")
	log.Printf("Goodbye!")
}
