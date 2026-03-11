package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"sync"
	"time"

	"github.com/go-redis/redis/v8"
)

func main() {
	var (
		meteorHost   = flag.String("meteor-host", "localhost", "Meteor server host")
		meteorPort   = flag.Int("meteor-port", 6380, "Meteor server port")
		redisHost    = flag.String("redis-host", "localhost", "Redis server host")
		redisPort    = flag.Int("redis-port", 6379, "Redis server port")
		numThreads   = flag.Int("threads", 4, "Number of threads")
		numRequests  = flag.Int("requests", 10000, "Number of requests per thread")
		valueSize    = flag.Int("value-size", 1024, "Size of values in bytes")
		keyPrefix    = flag.String("key-prefix", "bench:key:", "Key prefix")
		testDuration = flag.Duration("duration", 30*time.Second, "Test duration")
		pipelineSize = flag.Int("pipeline", 1, "Pipeline size")
		readRatio    = flag.Float64("read-ratio", 0.8, "Read ratio (0.0 to 1.0)")
	)
	flag.Parse()

	fmt.Printf("=== Meteor vs Redis Performance Benchmark ===\n")
	fmt.Printf("Threads: %d\n", *numThreads)
	fmt.Printf("Requests per thread: %d\n", *numRequests)
	fmt.Printf("Value size: %d bytes\n", *valueSize)
	fmt.Printf("Pipeline size: %d\n", *pipelineSize)
	fmt.Printf("Read ratio: %.1f%%\n", *readRatio*100)
	fmt.Printf("Test duration: %v\n", *testDuration)
	fmt.Printf("\n")

	// Test Meteor server
	fmt.Printf("Testing Meteor server (%s:%d)...\n", *meteorHost, *meteorPort)
	if err := waitForServer(*meteorHost, *meteorPort); err != nil {
		log.Fatalf("Meteor server not available: %v", err)
	}
	meteorResults := runBenchmark(*meteorHost, *meteorPort, *numThreads, *numRequests, *valueSize, *keyPrefix, *testDuration, *pipelineSize, *readRatio)

	// Test Redis server
	fmt.Printf("Testing Redis server (%s:%d)...\n", *redisHost, *redisPort)
	if err := waitForServer(*redisHost, *redisPort); err != nil {
		log.Fatalf("Redis server not available: %v", err)
	}
	redisResults := runBenchmark(*redisHost, *redisPort, *numThreads, *numRequests, *valueSize, *keyPrefix, *testDuration, *pipelineSize, *readRatio)

	// Print comparison
	fmt.Printf("\n=== Performance Comparison ===\n")
	fmt.Printf("Metric                  | Meteor        | Redis         | Improvement\n")
	fmt.Printf("------------------------|---------------|---------------|-------------\n")
	fmt.Printf("Total Operations        | %13d | %13d | %+.1f%%\n",
		meteorResults.TotalOps, redisResults.TotalOps,
		float64(meteorResults.TotalOps-redisResults.TotalOps)/float64(redisResults.TotalOps)*100)
	fmt.Printf("Throughput (ops/sec)    | %13.0f | %13.0f | %+.1f%%\n",
		meteorResults.Throughput, redisResults.Throughput,
		(meteorResults.Throughput-redisResults.Throughput)/redisResults.Throughput*100)
	fmt.Printf("Average Latency (μs)    | %13.0f | %13.0f | %+.1f%%\n",
		meteorResults.AvgLatency, redisResults.AvgLatency,
		(meteorResults.AvgLatency-redisResults.AvgLatency)/redisResults.AvgLatency*100)
	fmt.Printf("P50 Latency (μs)        | %13.0f | %13.0f | %+.1f%%\n",
		meteorResults.P50Latency, redisResults.P50Latency,
		(meteorResults.P50Latency-redisResults.P50Latency)/redisResults.P50Latency*100)
	fmt.Printf("P95 Latency (μs)        | %13.0f | %13.0f | %+.1f%%\n",
		meteorResults.P95Latency, redisResults.P95Latency,
		(meteorResults.P95Latency-redisResults.P95Latency)/redisResults.P95Latency*100)
	fmt.Printf("P99 Latency (μs)        | %13.0f | %13.0f | %+.1f%%\n",
		meteorResults.P99Latency, redisResults.P99Latency,
		(meteorResults.P99Latency-redisResults.P99Latency)/redisResults.P99Latency*100)
	fmt.Printf("Error Rate              | %12.2f%% | %12.2f%% | %+.1f%%\n",
		meteorResults.ErrorRate*100, redisResults.ErrorRate*100,
		(meteorResults.ErrorRate-redisResults.ErrorRate)*100)
}

type BenchmarkResult struct {
	TotalOps   int64
	Throughput float64
	AvgLatency float64
	P50Latency float64
	P95Latency float64
	P99Latency float64
	ErrorRate  float64
	Duration   time.Duration
}

func waitForServer(host string, port int) error {
	for i := 0; i < 30; i++ {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", host, port), time.Second)
		if err == nil {
			conn.Close()
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("server not available after 30 attempts")
}

func runBenchmark(host string, port int, numThreads, numRequests, valueSize int, keyPrefix string, testDuration time.Duration, pipelineSize int, readRatio float64) BenchmarkResult {
	var (
		totalOps    int64
		totalErrors int64
		latencies   []time.Duration
		mu          sync.Mutex
		wg          sync.WaitGroup
	)

	// Create Redis client
	client := redis.NewClient(&redis.Options{
		Addr:         fmt.Sprintf("%s:%d", host, port),
		Password:     "",
		DB:           0,
		PoolSize:     numThreads * 2,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
	})
	defer client.Close()

	// Test connection
	ctx := context.Background()
	if err := client.Ping(ctx).Err(); err != nil {
		log.Fatalf("Failed to connect to server: %v", err)
	}

	// Generate test data
	testValue := make([]byte, valueSize)
	for i := range testValue {
		testValue[i] = byte(i % 256)
	}

	startTime := time.Now()
	endTime := startTime.Add(testDuration)

	// Launch worker threads
	for i := 0; i < numThreads; i++ {
		wg.Add(1)
		go func(threadID int) {
			defer wg.Done()

			threadLatencies := make([]time.Duration, 0, numRequests)
			var threadOps, threadErrors int64

			for j := 0; j < numRequests && time.Now().Before(endTime); j++ {
				key := fmt.Sprintf("%s%d:%d", keyPrefix, threadID, j)

				// Determine operation type
				isRead := float64(j%100) < readRatio*100

				opStart := time.Now()
				var err error

				if isRead && j > 0 {
					// GET operation
					_, err = client.Get(ctx, key).Result()
					if err != nil && err != redis.Nil {
						threadErrors++
					}
				} else {
					// SET operation
					err = client.Set(ctx, key, testValue, 0).Err()
					if err != nil {
						threadErrors++
					}
				}

				latency := time.Since(opStart)
				threadLatencies = append(threadLatencies, latency)
				threadOps++
			}

			// Aggregate results
			mu.Lock()
			totalOps += threadOps
			totalErrors += threadErrors
			latencies = append(latencies, threadLatencies...)
			mu.Unlock()
		}(i)
	}

	wg.Wait()
	duration := time.Since(startTime)

	// Calculate statistics
	if len(latencies) == 0 {
		return BenchmarkResult{}
	}

	// Sort latencies for percentile calculation
	for i := 0; i < len(latencies); i++ {
		for j := i + 1; j < len(latencies); j++ {
			if latencies[i] > latencies[j] {
				latencies[i], latencies[j] = latencies[j], latencies[i]
			}
		}
	}

	var totalLatency time.Duration
	for _, lat := range latencies {
		totalLatency += lat
	}

	avgLatency := float64(totalLatency) / float64(len(latencies)) / float64(time.Microsecond)
	p50Latency := float64(latencies[len(latencies)*50/100]) / float64(time.Microsecond)
	p95Latency := float64(latencies[len(latencies)*95/100]) / float64(time.Microsecond)
	p99Latency := float64(latencies[len(latencies)*99/100]) / float64(time.Microsecond)

	return BenchmarkResult{
		TotalOps:   totalOps,
		Throughput: float64(totalOps) / duration.Seconds(),
		AvgLatency: avgLatency,
		P50Latency: p50Latency,
		P95Latency: p95Latency,
		P99Latency: p99Latency,
		ErrorRate:  float64(totalErrors) / float64(totalOps),
		Duration:   duration,
	}
}
