package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"os"
	"sort"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
)

func main() {
	// Create a temporary directory for testing
	tmpDir := "/tmp/meteor-perf-test-" + fmt.Sprintf("%d", time.Now().Unix())
	defer os.RemoveAll(tmpDir)

	// Create SSD cache with proper config
	config := &cache.Config{
		BaseDir:          tmpDir,
		MaxMemoryEntries: 1000,
		EntryTTL:         time.Hour,
		PageSize:         4096,
		MaxFileSize:      1024 * 1024 * 1024,
	}

	ssdCache, err := cache.NewSSDCache(config)
	if err != nil {
		log.Fatalf("Failed to create SSD cache: %v", err)
	}
	defer ssdCache.Close()

	fmt.Println("=== Meteor SSD Cache Performance Test ===")
	fmt.Printf("Test Directory: %s\n", tmpDir)
	fmt.Printf("Page Size: %d bytes\n", config.PageSize)
	fmt.Printf("Max File Size: %d bytes\n", config.MaxFileSize)
	fmt.Printf("Max Memory Entries: %d\n", config.MaxMemoryEntries)
	fmt.Println()

	// Run performance tests
	runWritePerformanceTest(ssdCache)
	runReadPerformanceTest(ssdCache)
	runMixedPerformanceTest(ssdCache)
}

func runWritePerformanceTest(cacheInstance *cache.SSDCache) {
	fmt.Println("1. Write Performance Test")
	fmt.Println("-------------------------")

	ctx := context.Background()
	numOps := 1000
	valueSize := 1024 // 1KB values
	latencies := make([]time.Duration, numOps)

	fmt.Printf("Testing %d PUT operations (1KB values):\n", numOps)

	start := time.Now()
	for i := 0; i < numOps; i++ {
		key := fmt.Sprintf("perf:write:%08d", i)
		value := randomBytes(valueSize)

		opStart := time.Now()
		err := cacheInstance.Put(ctx, key, value)
		latencies[i] = time.Since(opStart)

		if err != nil {
			fmt.Printf("Error in PUT operation %d: %v\n", i, err)
		}
	}
	totalDuration := time.Since(start)

	// Sort latencies for percentile calculation
	sort.Slice(latencies, func(i, j int) bool {
		return latencies[i] < latencies[j]
	})

	// Calculate statistics
	var total time.Duration
	for _, lat := range latencies {
		total += lat
	}
	avg := total / time.Duration(len(latencies))

	fmt.Printf("Total Duration: %v\n", totalDuration)
	fmt.Printf("Throughput: %.2f ops/sec\n", float64(numOps)/totalDuration.Seconds())
	fmt.Printf("Average Write Latency: %v\n", avg)
	fmt.Printf("Min Write Latency: %v\n", latencies[0])
	fmt.Printf("Max Write Latency: %v\n", latencies[len(latencies)-1])
	fmt.Printf("P50 Write Latency: %v\n", latencies[len(latencies)*50/100])
	fmt.Printf("P90 Write Latency: %v\n", latencies[len(latencies)*90/100])
	fmt.Printf("P95 Write Latency: %v\n", latencies[len(latencies)*95/100])
	fmt.Printf("P99 Write Latency: %v\n", latencies[len(latencies)*99/100])
	fmt.Println()
}

func runReadPerformanceTest(cacheInstance *cache.SSDCache) {
	fmt.Println("2. Read Performance Test")
	fmt.Println("------------------------")

	ctx := context.Background()
	numOps := 1000
	valueSize := 1024

	// First, write some data
	keys := make([]string, numOps)
	for i := 0; i < numOps; i++ {
		keys[i] = fmt.Sprintf("perf:read:%08d", i)
		value := randomBytes(valueSize)
		err := cacheInstance.Put(ctx, keys[i], value)
		if err != nil {
			fmt.Printf("Error writing key %s: %v\n", keys[i], err)
		}
	}

	fmt.Printf("Testing %d GET operations (1KB values):\n", numOps)

	// Now measure read latencies
	latencies := make([]time.Duration, numOps)
	hits := 0
	errors := 0

	start := time.Now()
	for i := 0; i < numOps; i++ {
		opStart := time.Now()
		data, err := cacheInstance.Get(ctx, keys[i])
		latencies[i] = time.Since(opStart)

		if err != nil {
			errors++
		} else if data != nil {
			hits++
		}
	}
	totalDuration := time.Since(start)

	// Sort latencies for percentile calculation
	sort.Slice(latencies, func(i, j int) bool {
		return latencies[i] < latencies[j]
	})

	// Calculate statistics
	var total time.Duration
	for _, lat := range latencies {
		total += lat
	}
	avg := total / time.Duration(len(latencies))

	fmt.Printf("Total Duration: %v\n", totalDuration)
	fmt.Printf("Throughput: %.2f ops/sec\n", float64(numOps)/totalDuration.Seconds())
	fmt.Printf("Average Read Latency: %v\n", avg)
	fmt.Printf("Min Read Latency: %v\n", latencies[0])
	fmt.Printf("Max Read Latency: %v\n", latencies[len(latencies)-1])
	fmt.Printf("P50 Read Latency: %v\n", latencies[len(latencies)*50/100])
	fmt.Printf("P90 Read Latency: %v\n", latencies[len(latencies)*90/100])
	fmt.Printf("P95 Read Latency: %v\n", latencies[len(latencies)*95/100])
	fmt.Printf("P99 Read Latency: %v\n", latencies[len(latencies)*99/100])
	fmt.Printf("Hit Rate: %.2f%% (%d hits, %d errors)\n", float64(hits)/float64(numOps)*100, hits, errors)
	fmt.Println()
}

func runMixedPerformanceTest(cacheInstance *cache.SSDCache) {
	fmt.Println("3. Mixed Workload Performance Test")
	fmt.Println("----------------------------------")

	ctx := context.Background()
	numOps := 2000
	valueSize := 512
	readRatio := 0.7 // 70% reads, 30% writes

	// Pre-populate some data
	baseKeys := make([]string, numOps/2)
	for i := 0; i < len(baseKeys); i++ {
		baseKeys[i] = fmt.Sprintf("perf:mixed:%08d", i)
		value := randomBytes(valueSize)
		err := cacheInstance.Put(ctx, baseKeys[i], value)
		if err != nil {
			fmt.Printf("Error writing key %s: %v\n", baseKeys[i], err)
		}
	}

	fmt.Printf("Testing %d mixed operations (70%% reads, 30%% writes, 512B values):\n", numOps)

	var readLatencies, writeLatencies []time.Duration
	var reads, writes, hits, readErrors, writeErrors int

	start := time.Now()
	for i := 0; i < numOps; i++ {
		if rand.Float64() < readRatio {
			// Read operation
			reads++
			key := baseKeys[rand.Intn(len(baseKeys))]

			opStart := time.Now()
			data, err := cacheInstance.Get(ctx, key)
			latency := time.Since(opStart)
			readLatencies = append(readLatencies, latency)

			if err != nil {
				readErrors++
			} else if data != nil {
				hits++
			}
		} else {
			// Write operation
			writes++
			key := fmt.Sprintf("perf:mixed:new:%08d", i)
			value := randomBytes(valueSize)

			opStart := time.Now()
			err := cacheInstance.Put(ctx, key, value)
			latency := time.Since(opStart)
			writeLatencies = append(writeLatencies, latency)

			if err != nil {
				writeErrors++
			}
		}
	}
	totalDuration := time.Since(start)

	fmt.Printf("Total Duration: %v\n", totalDuration)
	fmt.Printf("Total Throughput: %.2f ops/sec\n", float64(numOps)/totalDuration.Seconds())
	fmt.Printf("Operations: %d reads, %d writes\n", reads, writes)
	fmt.Printf("Read Hit Rate: %.2f%% (%d hits, %d errors)\n", float64(hits)/float64(reads)*100, hits, readErrors)
	fmt.Printf("Write Errors: %d\n", writeErrors)

	// Calculate read statistics
	if len(readLatencies) > 0 {
		sort.Slice(readLatencies, func(i, j int) bool {
			return readLatencies[i] < readLatencies[j]
		})

		var totalRead time.Duration
		for _, lat := range readLatencies {
			totalRead += lat
		}
		avgRead := totalRead / time.Duration(len(readLatencies))

		fmt.Printf("Read Latency - Avg: %v, P50: %v, P95: %v, P99: %v\n",
			avgRead,
			readLatencies[len(readLatencies)*50/100],
			readLatencies[len(readLatencies)*95/100],
			readLatencies[len(readLatencies)*99/100])
	}

	// Calculate write statistics
	if len(writeLatencies) > 0 {
		sort.Slice(writeLatencies, func(i, j int) bool {
			return writeLatencies[i] < writeLatencies[j]
		})

		var totalWrite time.Duration
		for _, lat := range writeLatencies {
			totalWrite += lat
		}
		avgWrite := totalWrite / time.Duration(len(writeLatencies))

		fmt.Printf("Write Latency - Avg: %v, P50: %v, P95: %v, P99: %v\n",
			avgWrite,
			writeLatencies[len(writeLatencies)*50/100],
			writeLatencies[len(writeLatencies)*95/100],
			writeLatencies[len(writeLatencies)*99/100])
	}

	fmt.Println()
}

func randomBytes(length int) []byte {
	b := make([]byte, length)
	rand.Read(b)
	return b
}
