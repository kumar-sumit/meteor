package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
)

func main() {
	fmt.Println("=== Meteor SSD Cache Sample Application ===")
	fmt.Println("Testing get/put operations with io_uring optimization")
	fmt.Println()

	// Create a temporary directory for the cache
	tempDir, err := os.MkdirTemp("", "meteor-cache-test")
	if err != nil {
		log.Fatalf("Failed to create temp directory: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Create configuration for optimized SSD cache
	config := &cache.Config{
		BaseDir:          tempDir,
		PageSize:         4096,
		MaxFileSize:      1024 * 1024 * 100, // 100MB
		MaxMemoryEntries: 1000,
		EntryTTL:         time.Hour,
	}

	// Create optimized cache instance
	fmt.Println("Creating optimized SSD cache...")
	cache, err := cache.NewOptimizedSSDCache(config)
	if err != nil {
		log.Fatalf("Failed to create cache: %v", err)
	}
	defer cache.Close()

	ctx := context.Background()

	// Test data
	testData := []struct {
		key   string
		value []byte
	}{
		{"user:123", []byte(`{"name": "John Doe", "age": 30, "city": "New York"}`)},
		{"user:456", []byte(`{"name": "Jane Smith", "age": 25, "city": "Los Angeles"}`)},
		{"product:789", []byte(`{"id": 789, "name": "Laptop", "price": 999.99, "category": "Electronics"}`)},
		{"order:101", []byte(`{"id": 101, "customer": "John Doe", "total": 1299.99, "items": [{"id": 789, "qty": 1}]}`)},
		{"session:abc123", []byte(`{"user_id": 123, "created_at": "2023-01-01T10:00:00Z", "expires_at": "2023-01-01T11:00:00Z"}`)},
	}

	// Test PUT operations
	fmt.Println("Testing PUT operations...")
	start := time.Now()
	for i, item := range testData {
		err := cache.Put(ctx, item.key, item.value)
		if err != nil {
			log.Printf("Failed to put key %s: %v", item.key, err)
			continue
		}
		fmt.Printf("  [%d] PUT %s: %d bytes\n", i+1, item.key, len(item.value))
	}
	putDuration := time.Since(start)
	fmt.Printf("PUT operations completed in %v\n", putDuration)
	fmt.Println()

	// Test GET operations
	fmt.Println("Testing GET operations...")
	start = time.Now()
	for i, item := range testData {
		retrievedValue, err := cache.Get(ctx, item.key)
		if err != nil {
			log.Printf("Failed to get key %s: %v", item.key, err)
			continue
		}
		if retrievedValue == nil {
			log.Printf("Key %s not found", item.key)
			continue
		}
		if string(retrievedValue) != string(item.value) {
			log.Printf("Value mismatch for key %s", item.key)
			continue
		}
		fmt.Printf("  [%d] GET %s: %d bytes ✓\n", i+1, item.key, len(retrievedValue))
	}
	getDuration := time.Since(start)
	fmt.Printf("GET operations completed in %v\n", getDuration)
	fmt.Println()

	// Test caching behavior - second read should be faster (from memory cache)
	fmt.Println("Testing cache performance (memory vs SSD)...")
	testKey := "performance:test"
	testValue := []byte("This is a test value for performance comparison")

	// First put
	err = cache.Put(ctx, testKey, testValue)
	if err != nil {
		log.Printf("Failed to put performance test key: %v", err)
	}

	// First get (from SSD)
	start = time.Now()
	_, err = cache.Get(ctx, testKey)
	if err != nil {
		log.Printf("Failed to get performance test key: %v", err)
	}
	ssdDuration := time.Since(start)

	// Second get (from memory cache)
	start = time.Now()
	_, err = cache.Get(ctx, testKey)
	if err != nil {
		log.Printf("Failed to get performance test key from memory: %v", err)
	}
	memoryDuration := time.Since(start)

	fmt.Printf("  SSD read: %v\n", ssdDuration)
	fmt.Printf("  Memory read: %v\n", memoryDuration)
	fmt.Printf("  Memory speedup: %.2fx\n", float64(ssdDuration)/float64(memoryDuration))
	fmt.Println()

	// Test Contains operation
	fmt.Println("Testing Contains operation...")
	for i, item := range testData {
		exists, err := cache.Contains(ctx, item.key)
		if err != nil {
			log.Printf("Failed to check if key %s exists: %v", item.key, err)
			continue
		}
		status := "✓"
		if !exists {
			status = "✗"
		}
		fmt.Printf("  [%d] Contains %s: %v %s\n", i+1, item.key, exists, status)
	}
	fmt.Println()

	// Test Remove operation
	fmt.Println("Testing Remove operation...")
	removeKey := "user:456"
	err = cache.Remove(ctx, removeKey)
	if err != nil {
		log.Printf("Failed to remove key %s: %v", removeKey, err)
	} else {
		fmt.Printf("  Removed key: %s\n", removeKey)
	}

	// Verify removal
	exists, err := cache.Contains(ctx, removeKey)
	if err != nil {
		log.Printf("Failed to check if removed key exists: %v", err)
	} else {
		fmt.Printf("  Key %s exists after removal: %v\n", removeKey, exists)
	}
	fmt.Println()

	// Show cache metrics
	fmt.Println("Cache Metrics:")
	metrics := cache.GetMetrics()
	fmt.Printf("  Hits: %d\n", metrics.Hits.Value())
	fmt.Printf("  Misses: %d\n", metrics.Misses.Value())
	fmt.Printf("  Hit Rate: %.2f%%\n", cache.GetHitRate()*100)
	fmt.Printf("  Memory Entries: %.0f\n", metrics.MemoryEntries.Value())
	fmt.Printf("  Evictions: %d\n", metrics.Evictions.Value())
	fmt.Println()

	// Show storage metrics
	fmt.Println("Storage Metrics:")
	storageMetrics := cache.GetStorageMetrics()
	fmt.Printf("  Bytes Read: %.0f\n", storageMetrics.BytesRead.Value())
	fmt.Printf("  Bytes Written: %.0f\n", storageMetrics.BytesWritten.Value())
	fmt.Printf("  I/O Errors: %.0f\n", storageMetrics.IOErrors.Value())
	fmt.Printf("  Queue Depth: %.0f\n", storageMetrics.QueueDepth.Value())
	fmt.Println()

	fmt.Println("=== Sample application completed successfully! ===")
}
