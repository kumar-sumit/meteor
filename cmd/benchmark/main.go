package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"runtime"
	"sync"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
	"github.com/go-redis/redis/v8"
)

const (
	testDurationSeconds = 5 // Reduced from 30 to 5 seconds
	numThreads          = 4 // Reduced from 10 to 4 threads
	keySize             = 10
	valueSize           = 100
)

func main() {
	fmt.Println("=== Meteor Cache vs Redis Performance Benchmark ===")
	fmt.Printf("Test Duration: %d seconds\n", testDurationSeconds)
	fmt.Printf("Threads: %d\n", numThreads)
	fmt.Printf("Key Size: %d bytes\n", keySize)
	fmt.Printf("Value Size: %d bytes\n", valueSize)
	fmt.Printf("CPU Cores: %d\n", runtime.NumCPU())
	fmt.Println()

	// Benchmark Meteor Cache
	fmt.Println("🚀 Benchmarking Meteor Cache...")
	meteorResults := benchmarkMeteorCache()
	fmt.Printf("Meteor Cache Results:\n")
	fmt.Printf("  Total Operations: %d\n", meteorResults.TotalOps)
	fmt.Printf("  Operations/sec: %.2f\n", meteorResults.OpsPerSecond)
	fmt.Printf("  Average Latency: %v\n", meteorResults.AvgLatency)
	fmt.Printf("  P50 Latency: %v\n", meteorResults.P50Latency)
	fmt.Printf("  P95 Latency: %v\n", meteorResults.P95Latency)
	fmt.Printf("  P99 Latency: %v\n", meteorResults.P99Latency)
	fmt.Printf("  Read Ops: %d (%.2f ops/sec)\n", meteorResults.ReadOps, meteorResults.ReadOpsPerSecond)
	fmt.Printf("  Write Ops: %d (%.2f ops/sec)\n", meteorResults.WriteOps, meteorResults.WriteOpsPerSecond)
	fmt.Println()

	// Benchmark Redis
	fmt.Println("🔴 Benchmarking Redis...")
	redisResults := benchmarkRedis()
	fmt.Printf("Redis Results:\n")
	fmt.Printf("  Total Operations: %d\n", redisResults.TotalOps)
	fmt.Printf("  Operations/sec: %.2f\n", redisResults.OpsPerSecond)
	fmt.Printf("  Average Latency: %v\n", redisResults.AvgLatency)
	fmt.Printf("  P50 Latency: %v\n", redisResults.P50Latency)
	fmt.Printf("  P95 Latency: %v\n", redisResults.P95Latency)
	fmt.Printf("  P99 Latency: %v\n", redisResults.P99Latency)
	fmt.Printf("  Read Ops: %d (%.2f ops/sec)\n", redisResults.ReadOps, redisResults.ReadOpsPerSecond)
	fmt.Printf("  Write Ops: %d (%.2f ops/sec)\n", redisResults.WriteOps, redisResults.WriteOpsPerSecond)
	fmt.Println()

	// Comparison
	fmt.Println("📊 Performance Comparison:")
	fmt.Printf("  Total Throughput: Meteor %.2fx faster than Redis\n", meteorResults.OpsPerSecond/redisResults.OpsPerSecond)
	fmt.Printf("  Read Throughput: Meteor %.2fx faster than Redis\n", meteorResults.ReadOpsPerSecond/redisResults.ReadOpsPerSecond)
	fmt.Printf("  Write Throughput: Meteor %.2fx faster than Redis\n", meteorResults.WriteOpsPerSecond/redisResults.WriteOpsPerSecond)
	fmt.Printf("  Average Latency: Meteor %.2fx faster than Redis\n", float64(redisResults.AvgLatency)/float64(meteorResults.AvgLatency))
	fmt.Printf("  P99 Latency: Meteor %.2fx faster than Redis\n", float64(redisResults.P99Latency)/float64(meteorResults.P99Latency))
	fmt.Println()

	fmt.Println("✅ Benchmark completed!")
}

type BenchmarkResult struct {
	TotalOps          int64
	OpsPerSecond      float64
	ReadOps           int64
	WriteOps          int64
	ReadOpsPerSecond  float64
	WriteOpsPerSecond float64
	AvgLatency        time.Duration
	P50Latency        time.Duration
	P95Latency        time.Duration
	P99Latency        time.Duration
	Latencies         []time.Duration
}

func benchmarkMeteorCache() *BenchmarkResult {
	fmt.Println("  Setting up Meteor cache...")

	// Create temporary directory for cache
	tempDir, err := os.MkdirTemp("", "meteor-bench")
	if err != nil {
		log.Fatalf("Failed to create temp directory: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Create cache configuration
	config := &cache.Config{
		BaseDir:          tempDir,
		PageSize:         4096,
		MaxFileSize:      1024 * 1024 * 100, // 100MB (reduced from 1GB)
		MaxMemoryEntries: 1000,              // Reduced from 10000
		EntryTTL:         time.Hour,
	}

	// Create cache instance
	cache, err := cache.NewOptimizedSSDCache(config)
	if err != nil {
		log.Fatalf("Failed to create cache: %v", err)
	}
	defer cache.Close()

	fmt.Println("  Running benchmark...")
	return runBenchmark(func(ctx context.Context, key string, value []byte, isRead bool) error {
		if isRead {
			_, err := cache.Get(ctx, key)
			return err
		} else {
			return cache.Put(ctx, key, value, time.Hour)
		}
	})
}

func benchmarkRedis() *BenchmarkResult {
	fmt.Println("  Setting up Redis connection...")

	// Create Redis client
	rdb := redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
		DB:   0,
	})
	defer rdb.Close()

	// Test Redis connection
	ctx := context.Background()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}

	fmt.Println("  Running benchmark...")
	return runBenchmark(func(ctx context.Context, key string, value []byte, isRead bool) error {
		if isRead {
			return rdb.Get(ctx, key).Err()
		} else {
			return rdb.Set(ctx, key, value, 0).Err()
		}
	})
}

func runBenchmark(operation func(ctx context.Context, key string, value []byte, isRead bool) error) *BenchmarkResult {
	var wg sync.WaitGroup
	var mutex sync.Mutex
	var totalOps int64
	var readOps int64
	var writeOps int64
	var latencies []time.Duration

	ctx := context.Background()
	done := make(chan struct{})

	// Generate test data
	testValue := make([]byte, valueSize)
	for i := range testValue {
		testValue[i] = byte(i % 256)
	}

	// Pre-populate some data for reads (reduced from 1000 to 100)
	for i := 0; i < 100; i++ {
		key := fmt.Sprintf("key_%010d", i)
		operation(ctx, key, testValue, false)
	}

	// Start benchmark timer
	startTime := time.Now()
	go func() {
		time.Sleep(time.Duration(testDurationSeconds) * time.Second)
		close(done)
	}()

	// Start worker threads
	for i := 0; i < numThreads; i++ {
		wg.Add(1)
		go func(threadID int) {
			defer wg.Done()

			keyCounter := threadID * 100000 // Spread keys across threads

			for {
				select {
				case <-done:
					return
				default:
					// 80% reads, 20% writes
					isRead := (keyCounter % 5) != 0
					key := fmt.Sprintf("key_%010d", keyCounter%1000) // Reduced from 10000 to 1000

					opStart := time.Now()
					err := operation(ctx, key, testValue, isRead)
					latency := time.Since(opStart)

					mutex.Lock()
					totalOps++
					latencies = append(latencies, latency)
					if isRead {
						readOps++
					} else {
						writeOps++
					}
					mutex.Unlock()

					if err != nil && err != redis.Nil {
						// Ignore Redis key not found errors
						log.Printf("Operation error: %v", err)
					}

					keyCounter++

					// Add small sleep to avoid overwhelming the system
					time.Sleep(time.Microsecond * 100)
				}
			}
		}(i)
	}

	wg.Wait()
	totalDuration := time.Since(startTime)

	// Calculate statistics
	opsPerSecond := float64(totalOps) / totalDuration.Seconds()
	readOpsPerSecond := float64(readOps) / totalDuration.Seconds()
	writeOpsPerSecond := float64(writeOps) / totalDuration.Seconds()

	// Calculate latency percentiles
	if len(latencies) == 0 {
		return &BenchmarkResult{
			TotalOps:          totalOps,
			OpsPerSecond:      opsPerSecond,
			ReadOps:           readOps,
			WriteOps:          writeOps,
			ReadOpsPerSecond:  readOpsPerSecond,
			WriteOpsPerSecond: writeOpsPerSecond,
		}
	}

	// Sort latencies for percentile calculation
	sortLatencies(latencies)

	avgLatency := calculateAverage(latencies)
	p50Latency := latencies[len(latencies)*50/100]
	p95Latency := latencies[len(latencies)*95/100]
	p99Latency := latencies[len(latencies)*99/100]

	return &BenchmarkResult{
		TotalOps:          totalOps,
		OpsPerSecond:      opsPerSecond,
		ReadOps:           readOps,
		WriteOps:          writeOps,
		ReadOpsPerSecond:  readOpsPerSecond,
		WriteOpsPerSecond: writeOpsPerSecond,
		AvgLatency:        avgLatency,
		P50Latency:        p50Latency,
		P95Latency:        p95Latency,
		P99Latency:        p99Latency,
		Latencies:         latencies,
	}
}

func sortLatencies(latencies []time.Duration) {
	// Simple bubble sort for demonstration
	n := len(latencies)
	for i := 0; i < n-1; i++ {
		for j := 0; j < n-i-1; j++ {
			if latencies[j] > latencies[j+1] {
				latencies[j], latencies[j+1] = latencies[j+1], latencies[j]
			}
		}
	}
}

func calculateAverage(latencies []time.Duration) time.Duration {
	if len(latencies) == 0 {
		return 0
	}

	var sum time.Duration
	for _, latency := range latencies {
		sum += latency
	}
	return sum / time.Duration(len(latencies))
}
