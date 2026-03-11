package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"net"
	"runtime"
	"sort"
	"sync"
	"sync/atomic"
	"time"
)

// BenchmarkResult holds the results of a benchmark run
type BenchmarkResult struct {
	ServerType          string
	Address             string
	Port                int
	Duration            time.Duration
	TotalOperations     int64
	TotalErrors         int64
	OperationsPerSecond float64
	AverageLatency      time.Duration
	P50Latency          time.Duration
	P95Latency          time.Duration
	P99Latency          time.Duration
	MinLatency          time.Duration
	MaxLatency          time.Duration
	MemoryUsage         int64
	CPUUsage            float64
}

// BenchmarkConfig holds benchmark configuration
type BenchmarkConfig struct {
	Connections   int
	Duration      time.Duration
	KeySize       int
	ValueSize     int
	ReadRatio     float64
	WriteRatio    float64
	KeySpaceSize  int
	PrintInterval time.Duration
}

// LatencyTracker tracks latency statistics
type LatencyTracker struct {
	latencies []time.Duration
	mutex     sync.Mutex
}

func NewLatencyTracker() *LatencyTracker {
	return &LatencyTracker{
		latencies: make([]time.Duration, 0, 1000000),
	}
}

func (lt *LatencyTracker) Record(latency time.Duration) {
	lt.mutex.Lock()
	defer lt.mutex.Unlock()
	lt.latencies = append(lt.latencies, latency)
}

func (lt *LatencyTracker) GetStats() (min, max, avg, p50, p95, p99 time.Duration) {
	lt.mutex.Lock()
	defer lt.mutex.Unlock()

	if len(lt.latencies) == 0 {
		return 0, 0, 0, 0, 0, 0
	}

	// Sort latencies
	sort.Slice(lt.latencies, func(i, j int) bool {
		return lt.latencies[i] < lt.latencies[j]
	})

	min = lt.latencies[0]
	max = lt.latencies[len(lt.latencies)-1]

	// Calculate average
	var total time.Duration
	for _, latency := range lt.latencies {
		total += latency
	}
	avg = total / time.Duration(len(lt.latencies))

	// Calculate percentiles
	p50 = lt.latencies[len(lt.latencies)*50/100]
	p95 = lt.latencies[len(lt.latencies)*95/100]
	p99 = lt.latencies[len(lt.latencies)*99/100]

	return min, max, avg, p50, p95, p99
}

// BenchmarkClient represents a benchmark client
type BenchmarkClient struct {
	id             int
	address        string
	port           int
	config         *BenchmarkConfig
	conn           net.Conn
	operations     int64
	errors         int64
	latencyTracker *LatencyTracker
	ctx            context.Context
	cancel         context.CancelFunc
	wg             sync.WaitGroup
}

func NewBenchmarkClient(id int, address string, port int, config *BenchmarkConfig) *BenchmarkClient {
	ctx, cancel := context.WithCancel(context.Background())

	return &BenchmarkClient{
		id:             id,
		address:        address,
		port:           port,
		config:         config,
		latencyTracker: NewLatencyTracker(),
		ctx:            ctx,
		cancel:         cancel,
	}
}

func (bc *BenchmarkClient) Connect() error {
	conn, err := net.Dial("tcp", fmt.Sprintf("%s:%d", bc.address, bc.port))
	if err != nil {
		return fmt.Errorf("failed to connect: %w", err)
	}

	bc.conn = conn
	return nil
}

func (bc *BenchmarkClient) Close() {
	bc.cancel()
	bc.wg.Wait()

	if bc.conn != nil {
		bc.conn.Close()
	}
}

func (bc *BenchmarkClient) sendCommand(command string) (string, error) {
	start := time.Now()

	// Send command
	if _, err := bc.conn.Write([]byte(command)); err != nil {
		return "", err
	}

	// Read response
	reader := bufio.NewReader(bc.conn)
	response, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}

	// If it's a bulk string, read the actual data
	if len(response) > 0 && response[0] == '$' {
		// Read length
		var length int
		if _, err := fmt.Sscanf(response[1:], "%d", &length); err == nil && length > 0 {
			// Read data
			data := make([]byte, length)
			if _, err := bc.conn.Read(data); err != nil {
				return "", err
			}
			// Read trailing CRLF
			if _, err := reader.ReadString('\n'); err != nil {
				return "", err
			}
			response = string(data)
		}
	}

	latency := time.Since(start)
	bc.latencyTracker.Record(latency)

	return response, nil
}

func (bc *BenchmarkClient) Run() {
	bc.wg.Add(1)
	go bc.worker()
}

func (bc *BenchmarkClient) worker() {
	defer bc.wg.Done()

	keyPrefix := fmt.Sprintf("bench:key:%d:", bc.id)
	value := make([]byte, bc.config.ValueSize)
	for i := range value {
		value[i] = byte('a' + (i % 26))
	}

	for {
		select {
		case <-bc.ctx.Done():
			return
		default:
			// Decide operation type
			isRead := (float64(atomic.LoadInt64(&bc.operations)) / float64(atomic.LoadInt64(&bc.operations)+1)) < bc.config.ReadRatio

			keyNum := int(atomic.LoadInt64(&bc.operations)) % bc.config.KeySpaceSize
			key := fmt.Sprintf("%s%d", keyPrefix, keyNum)

			var command string
			if isRead {
				command = fmt.Sprintf("*2\r\n$3\r\nGET\r\n$%d\r\n%s\r\n", len(key), key)
			} else {
				command = fmt.Sprintf("*3\r\n$3\r\nSET\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n", len(key), key, len(value), string(value))
			}

			_, err := bc.sendCommand(command)
			if err != nil {
				atomic.AddInt64(&bc.errors, 1)
				continue
			}

			atomic.AddInt64(&bc.operations, 1)
		}
	}
}

// BenchmarkRunner coordinates the benchmark execution
type BenchmarkRunner struct {
	serverType string
	address    string
	port       int
	config     *BenchmarkConfig
	clients    []*BenchmarkClient
	startTime  time.Time
	endTime    time.Time
}

func NewBenchmarkRunner(serverType, address string, port int, config *BenchmarkConfig) *BenchmarkRunner {
	return &BenchmarkRunner{
		serverType: serverType,
		address:    address,
		port:       port,
		config:     config,
		clients:    make([]*BenchmarkClient, config.Connections),
	}
}

func (br *BenchmarkRunner) Run() (*BenchmarkResult, error) {
	fmt.Printf("🚀 Starting benchmark for %s on %s:%d\n", br.serverType, br.address, br.port)
	fmt.Printf("   Connections: %d\n", br.config.Connections)
	fmt.Printf("   Duration: %v\n", br.config.Duration)
	fmt.Printf("   Key size: %d bytes\n", br.config.KeySize)
	fmt.Printf("   Value size: %d bytes\n", br.config.ValueSize)
	fmt.Printf("   Read ratio: %.2f\n", br.config.ReadRatio)
	fmt.Printf("   Write ratio: %.2f\n", br.config.WriteRatio)
	fmt.Printf("   Key space size: %d\n", br.config.KeySpaceSize)

	// Create and connect clients
	for i := 0; i < br.config.Connections; i++ {
		client := NewBenchmarkClient(i, br.address, br.port, br.config)
		if err := client.Connect(); err != nil {
			return nil, fmt.Errorf("failed to connect client %d: %w", i, err)
		}
		br.clients[i] = client
	}

	// Start benchmark
	br.startTime = time.Now()
	for _, client := range br.clients {
		client.Run()
	}

	// Run for specified duration with periodic reporting
	progressTicker := time.NewTicker(br.config.PrintInterval)
	defer progressTicker.Stop()

	endTimer := time.NewTimer(br.config.Duration)
	defer endTimer.Stop()

	for {
		select {
		case <-progressTicker.C:
			br.printProgress()
		case <-endTimer.C:
			br.endTime = time.Now()

			// Stop all clients
			for _, client := range br.clients {
				client.Close()
			}

			return br.generateResult(), nil
		}
	}
}

func (br *BenchmarkRunner) printProgress() {
	elapsed := time.Since(br.startTime)
	totalOps := int64(0)
	totalErrors := int64(0)

	for _, client := range br.clients {
		totalOps += atomic.LoadInt64(&client.operations)
		totalErrors += atomic.LoadInt64(&client.errors)
	}

	opsPerSecond := float64(totalOps) / elapsed.Seconds()

	fmt.Printf("⏱️  %s: %v elapsed, %d ops, %d errors, %.2f ops/sec\n",
		br.serverType, elapsed.Truncate(time.Second), totalOps, totalErrors, opsPerSecond)
}

func (br *BenchmarkRunner) generateResult() *BenchmarkResult {
	totalOps := int64(0)
	totalErrors := int64(0)
	allLatencies := make([]time.Duration, 0)

	// Collect stats from all clients
	for _, client := range br.clients {
		totalOps += atomic.LoadInt64(&client.operations)
		totalErrors += atomic.LoadInt64(&client.errors)

		// Get latencies
		min, max, avg, p50, p95, p99 := client.latencyTracker.GetStats()
		_ = min
		_ = max
		_ = avg
		_ = p50
		_ = p95
		_ = p99

		client.latencyTracker.mutex.Lock()
		allLatencies = append(allLatencies, client.latencyTracker.latencies...)
		client.latencyTracker.mutex.Unlock()
	}

	// Calculate overall latency statistics
	sort.Slice(allLatencies, func(i, j int) bool {
		return allLatencies[i] < allLatencies[j]
	})

	var minLatency, maxLatency, avgLatency, p50Latency, p95Latency, p99Latency time.Duration

	if len(allLatencies) > 0 {
		minLatency = allLatencies[0]
		maxLatency = allLatencies[len(allLatencies)-1]

		// Calculate average
		var total time.Duration
		for _, latency := range allLatencies {
			total += latency
		}
		avgLatency = total / time.Duration(len(allLatencies))

		// Calculate percentiles
		p50Latency = allLatencies[len(allLatencies)*50/100]
		p95Latency = allLatencies[len(allLatencies)*95/100]
		p99Latency = allLatencies[len(allLatencies)*99/100]
	}

	duration := br.endTime.Sub(br.startTime)
	opsPerSecond := float64(totalOps) / duration.Seconds()

	return &BenchmarkResult{
		ServerType:          br.serverType,
		Address:             br.address,
		Port:                br.port,
		Duration:            duration,
		TotalOperations:     totalOps,
		TotalErrors:         totalErrors,
		OperationsPerSecond: opsPerSecond,
		AverageLatency:      avgLatency,
		P50Latency:          p50Latency,
		P95Latency:          p95Latency,
		P99Latency:          p99Latency,
		MinLatency:          minLatency,
		MaxLatency:          maxLatency,
		MemoryUsage:         getMemoryUsage(),
		CPUUsage:            getCPUUsage(),
	}
}

func getMemoryUsage() int64 {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	return int64(m.Alloc)
}

func getCPUUsage() float64 {
	// Simplified CPU usage calculation
	// In a real implementation, you'd want to use proper CPU monitoring
	return 0.0
}

// printResults prints detailed benchmark results
func printResults(results []*BenchmarkResult) {
	fmt.Printf("\n🏆 BENCHMARK RESULTS SUMMARY\n")
	fmt.Printf("═══════════════════════════════════════════════════════════════════════════════════════\n")

	for _, result := range results {
		fmt.Printf("\n📊 %s Results:\n", result.ServerType)
		fmt.Printf("   Address: %s:%d\n", result.Address, result.Port)
		fmt.Printf("   Duration: %v\n", result.Duration)
		fmt.Printf("   Total Operations: %d\n", result.TotalOperations)
		fmt.Printf("   Total Errors: %d\n", result.TotalErrors)
		fmt.Printf("   Operations/Second: %.2f\n", result.OperationsPerSecond)
		fmt.Printf("   Average Latency: %v\n", result.AverageLatency)
		fmt.Printf("   P50 Latency: %v\n", result.P50Latency)
		fmt.Printf("   P95 Latency: %v\n", result.P95Latency)
		fmt.Printf("   P99 Latency: %v\n", result.P99Latency)
		fmt.Printf("   Min Latency: %v\n", result.MinLatency)
		fmt.Printf("   Max Latency: %v\n", result.MaxLatency)
		fmt.Printf("   Memory Usage: %d bytes\n", result.MemoryUsage)
		fmt.Printf("   Error Rate: %.4f%%\n", float64(result.TotalErrors)/float64(result.TotalOperations)*100)
	}

	// Comparison table
	fmt.Printf("\n📈 PERFORMANCE COMPARISON\n")
	fmt.Printf("─────────────────────────────────────────────────────────────────────────────────────\n")
	fmt.Printf("%-15s %-12s %-12s %-12s %-12s %-12s\n", "Server", "Ops/Sec", "Avg Lat", "P50 Lat", "P95 Lat", "P99 Lat")
	fmt.Printf("─────────────────────────────────────────────────────────────────────────────────────\n")

	for _, result := range results {
		fmt.Printf("%-15s %-12.0f %-12s %-12s %-12s %-12s\n",
			result.ServerType,
			result.OperationsPerSecond,
			result.AverageLatency.Truncate(time.Microsecond),
			result.P50Latency.Truncate(time.Microsecond),
			result.P95Latency.Truncate(time.Microsecond),
			result.P99Latency.Truncate(time.Microsecond),
		)
	}

	// Find best performer
	if len(results) > 1 {
		best := results[0]
		for _, result := range results[1:] {
			if result.OperationsPerSecond > best.OperationsPerSecond {
				best = result
			}
		}

		fmt.Printf("\n🥇 Best Performer: %s (%.2f ops/sec)\n", best.ServerType, best.OperationsPerSecond)

		// Show performance ratios
		fmt.Printf("\n📊 Performance Ratios (vs %s):\n", best.ServerType)
		for _, result := range results {
			if result.ServerType != best.ServerType {
				ratio := best.OperationsPerSecond / result.OperationsPerSecond
				fmt.Printf("   %s: %.2fx slower\n", result.ServerType, ratio)
			}
		}
	}
}

// testServerConnection tests if a server is reachable
func testServerConnection(address string, port int) error {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", address, port), time.Second*5)
	if err != nil {
		return err
	}
	defer conn.Close()

	// Send PING command
	if _, err := conn.Write([]byte("*1\r\n$4\r\nPING\r\n")); err != nil {
		return err
	}

	// Read response
	reader := bufio.NewReader(conn)
	response, err := reader.ReadString('\n')
	if err != nil {
		return err
	}

	if response != "+PONG\r\n" {
		return fmt.Errorf("unexpected response: %s", response)
	}

	return nil
}

func main() {
	var (
		// Server configurations
		redisAddress     = flag.String("redis-address", "localhost", "Redis server address")
		redisPort        = flag.Int("redis-port", 6379, "Redis server port")
		dragonflyAddress = flag.String("dragonfly-address", "localhost", "Dragonfly server address")
		dragonflyPort    = flag.Int("dragonfly-port", 6380, "Dragonfly server port")
		meteorAddress    = flag.String("meteor-address", "localhost", "Meteor server address")
		meteorPort       = flag.Int("meteor-port", 6380, "Meteor server port")

		// Benchmark configuration
		connections   = flag.Int("connections", 50, "Number of concurrent connections")
		duration      = flag.Duration("duration", time.Minute, "Benchmark duration")
		keySize       = flag.Int("key-size", 16, "Key size in bytes")
		valueSize     = flag.Int("value-size", 100, "Value size in bytes")
		readRatio     = flag.Float64("read-ratio", 0.8, "Read operation ratio (0.0-1.0)")
		keySpaceSize  = flag.Int("key-space-size", 10000, "Key space size")
		printInterval = flag.Duration("print-interval", time.Second*5, "Progress print interval")

		// Server selection
		testRedis     = flag.Bool("test-redis", true, "Test Redis server")
		testDragonfly = flag.Bool("test-dragonfly", false, "Test Dragonfly server")
		testMeteor    = flag.Bool("test-meteor", true, "Test Meteor server")
	)
	flag.Parse()

	writeRatio := 1.0 - *readRatio

	config := &BenchmarkConfig{
		Connections:   *connections,
		Duration:      *duration,
		KeySize:       *keySize,
		ValueSize:     *valueSize,
		ReadRatio:     *readRatio,
		WriteRatio:    writeRatio,
		KeySpaceSize:  *keySpaceSize,
		PrintInterval: *printInterval,
	}

	var results []*BenchmarkResult

	// Test Redis
	if *testRedis {
		fmt.Printf("🔍 Testing Redis connection at %s:%d...\n", *redisAddress, *redisPort)
		if err := testServerConnection(*redisAddress, *redisPort); err != nil {
			fmt.Printf("❌ Redis connection failed: %v\n", err)
		} else {
			fmt.Printf("✅ Redis connection successful\n")
			runner := NewBenchmarkRunner("Redis", *redisAddress, *redisPort, config)
			result, err := runner.Run()
			if err != nil {
				fmt.Printf("❌ Redis benchmark failed: %v\n", err)
			} else {
				results = append(results, result)
			}
		}
	}

	// Test Dragonfly
	if *testDragonfly {
		fmt.Printf("🔍 Testing Dragonfly connection at %s:%d...\n", *dragonflyAddress, *dragonflyPort)
		if err := testServerConnection(*dragonflyAddress, *dragonflyPort); err != nil {
			fmt.Printf("❌ Dragonfly connection failed: %v\n", err)
		} else {
			fmt.Printf("✅ Dragonfly connection successful\n")
			runner := NewBenchmarkRunner("Dragonfly", *dragonflyAddress, *dragonflyPort, config)
			result, err := runner.Run()
			if err != nil {
				fmt.Printf("❌ Dragonfly benchmark failed: %v\n", err)
			} else {
				results = append(results, result)
			}
		}
	}

	// Test Meteor
	if *testMeteor {
		fmt.Printf("🔍 Testing Meteor connection at %s:%d...\n", *meteorAddress, *meteorPort)
		if err := testServerConnection(*meteorAddress, *meteorPort); err != nil {
			fmt.Printf("❌ Meteor connection failed: %v\n", err)
		} else {
			fmt.Printf("✅ Meteor connection successful\n")
			runner := NewBenchmarkRunner("Meteor Hybrid", *meteorAddress, *meteorPort, config)
			result, err := runner.Run()
			if err != nil {
				fmt.Printf("❌ Meteor benchmark failed: %v\n", err)
			} else {
				results = append(results, result)
			}
		}
	}

	// Print final results
	if len(results) > 0 {
		printResults(results)
	} else {
		fmt.Printf("❌ No benchmark results to display\n")
	}
}
