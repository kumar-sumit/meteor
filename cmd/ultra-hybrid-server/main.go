package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"github.com/kumar-sumit/meteor/pkg/cache"
)

// UltraHybridServer represents the ultra-optimized hybrid server
type UltraHybridServer struct {
	address     string
	port        int
	cache       *cache.HybridCache
	cacheConfig *cache.HybridCacheConfig
	listener    net.Listener
	connections sync.Map
	stats       *ServerStats

	// Configuration
	maxConnections int
	bufferSize     int
	gcPercent      int

	// Lifecycle
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

// ServerStats tracks server performance metrics
type ServerStats struct {
	totalConnections   int64
	currentConnections int64
	totalCommands      int64
	totalErrors        int64
	commandsPerSecond  float64
	startTime          time.Time
}

// UltraRESPParser implements zero-copy RESP parsing
type UltraRESPParser struct {
	reader *bufio.Reader
	buf    []byte
}

// NewUltraRESPParser creates a new ultra-fast RESP parser
func NewUltraRESPParser(r io.Reader, bufferSize int) *UltraRESPParser {
	return &UltraRESPParser{
		reader: bufio.NewReaderSize(r, bufferSize),
		buf:    make([]byte, 0, 4096),
	}
}

// ReadCommand reads a RESP command with zero-copy optimizations
func (p *UltraRESPParser) ReadCommand() ([][]byte, error) {
	// Read array length
	line, err := p.reader.ReadSlice('\n')
	if err != nil {
		return nil, err
	}

	if len(line) < 3 || line[0] != '*' {
		return nil, fmt.Errorf("invalid RESP array format")
	}

	// Parse array length
	argCount := 0
	for i := 1; i < len(line)-2; i++ {
		if line[i] >= '0' && line[i] <= '9' {
			argCount = argCount*10 + int(line[i]-'0')
		} else {
			return nil, fmt.Errorf("invalid array length")
		}
	}

	if argCount <= 0 {
		return nil, fmt.Errorf("invalid argument count")
	}

	// Read arguments
	args := make([][]byte, argCount)
	for i := 0; i < argCount; i++ {
		// Read bulk string length
		line, err := p.reader.ReadSlice('\n')
		if err != nil {
			return nil, err
		}

		if len(line) < 3 || line[0] != '$' {
			return nil, fmt.Errorf("invalid bulk string format")
		}

		// Parse bulk string length
		strLen := 0
		for j := 1; j < len(line)-2; j++ {
			if line[j] >= '0' && line[j] <= '9' {
				strLen = strLen*10 + int(line[j]-'0')
			} else {
				return nil, fmt.Errorf("invalid bulk string length")
			}
		}

		if strLen < 0 {
			return nil, fmt.Errorf("negative bulk string length")
		}

		// Read bulk string data
		argData := make([]byte, strLen)
		if _, err := io.ReadFull(p.reader, argData); err != nil {
			return nil, err
		}

		// Read trailing CRLF
		if _, err := p.reader.ReadSlice('\n'); err != nil {
			return nil, err
		}

		args[i] = argData
	}

	return args, nil
}

// writeResponse writes a RESP response with zero-copy optimizations
func writeResponse(w io.Writer, response []byte) error {
	if _, err := w.Write(response); err != nil {
		return err
	}
	return nil
}

// Pre-computed RESP responses for common operations
var (
	okResponse    = []byte("+OK\r\n")
	nullResponse  = []byte("$-1\r\n")
	errorResponse = []byte("-ERR unknown command\r\n")
	pongResponse  = []byte("+PONG\r\n")
	integerZero   = []byte(":0\r\n")
	integerOne    = []byte(":1\r\n")
)

// formatBulkString formats a bulk string response
func formatBulkString(value []byte) []byte {
	if value == nil {
		return nullResponse
	}

	lenStr := fmt.Sprintf("$%d\r\n", len(value))
	response := make([]byte, 0, len(lenStr)+len(value)+2)
	response = append(response, lenStr...)
	response = append(response, value...)
	response = append(response, '\r', '\n')
	return response
}

// handleConnection handles a client connection with ultra-fast processing
func (s *UltraHybridServer) handleConnection(conn net.Conn) {
	defer func() {
		conn.Close()
		s.connections.Delete(conn.RemoteAddr().String())
		atomic.AddInt64(&s.stats.currentConnections, -1)
	}()

	atomic.AddInt64(&s.stats.currentConnections, 1)
	s.connections.Store(conn.RemoteAddr().String(), conn)

	// Set TCP optimizations
	if tcpConn, ok := conn.(*net.TCPConn); ok {
		tcpConn.SetNoDelay(true)
		tcpConn.SetKeepAlive(true)
		tcpConn.SetKeepAlivePeriod(time.Second * 30)
	}

	parser := NewUltraRESPParser(conn, s.bufferSize)

	for {
		select {
		case <-s.ctx.Done():
			return
		default:
			// Set read timeout
			conn.SetReadDeadline(time.Now().Add(time.Second * 30))

			// Parse command
			args, err := parser.ReadCommand()
			if err != nil {
				if err != io.EOF {
					atomic.AddInt64(&s.stats.totalErrors, 1)
				}
				return
			}

			atomic.AddInt64(&s.stats.totalCommands, 1)

			// Process command
			response := s.processCommand(args)

			// Write response
			if err := writeResponse(conn, response); err != nil {
				atomic.AddInt64(&s.stats.totalErrors, 1)
				return
			}
		}
	}
}

// processCommand processes a Redis command with ultra-fast execution
func (s *UltraHybridServer) processCommand(args [][]byte) []byte {
	if len(args) == 0 {
		return errorResponse
	}

	// Convert command to uppercase using unsafe operations for speed
	command := strings.ToUpper(*(*string)(unsafe.Pointer(&args[0])))

	switch command {
	case "PING":
		return pongResponse

	case "GET":
		if len(args) != 2 {
			return []byte("-ERR wrong number of arguments for 'get' command\r\n")
		}

		key := *(*string)(unsafe.Pointer(&args[1]))
		value, err := s.cache.Get(context.Background(), key)
		if err != nil {
			return []byte("-ERR " + err.Error() + "\r\n")
		}

		return formatBulkString(value)

	case "SET":
		if len(args) < 3 {
			return []byte("-ERR wrong number of arguments for 'set' command\r\n")
		}

		key := *(*string)(unsafe.Pointer(&args[1]))
		value := args[2]

		// Handle optional EX parameter
		ttl := time.Hour // Default TTL
		if len(args) == 5 && strings.ToUpper(*(*string)(unsafe.Pointer(&args[3]))) == "EX" {
			// Parse TTL (simplified)
			ttlStr := *(*string)(unsafe.Pointer(&args[4]))
			if ttlSeconds := parseSimpleInt(ttlStr); ttlSeconds > 0 {
				ttl = time.Duration(ttlSeconds) * time.Second
			}
		}

		if err := s.cache.Put(context.Background(), key, value, ttl); err != nil {
			return []byte("-ERR " + err.Error() + "\r\n")
		}

		return okResponse

	case "DEL":
		if len(args) < 2 {
			return []byte("-ERR wrong number of arguments for 'del' command\r\n")
		}

		deleted := 0
		for i := 1; i < len(args); i++ {
			key := *(*string)(unsafe.Pointer(&args[i]))
			if err := s.cache.Remove(context.Background(), key); err == nil {
				deleted++
			}
		}

		return []byte(fmt.Sprintf(":%d\r\n", deleted))

	case "EXISTS":
		if len(args) != 2 {
			return []byte("-ERR wrong number of arguments for 'exists' command\r\n")
		}

		key := *(*string)(unsafe.Pointer(&args[1]))
		exists, err := s.cache.Contains(context.Background(), key)
		if err != nil {
			return []byte("-ERR " + err.Error() + "\r\n")
		}

		if exists {
			return integerOne
		}
		return integerZero

	case "FLUSHALL":
		if err := s.cache.Clear(context.Background()); err != nil {
			return []byte("-ERR " + err.Error() + "\r\n")
		}
		return okResponse

	case "INFO":
		stats := s.cache.GetStats()
		info := fmt.Sprintf("# Hybrid Cache Stats\r\n")
		info += fmt.Sprintf("memory_hits:%d\r\n", stats["memory_hits"])
		info += fmt.Sprintf("memory_misses:%d\r\n", stats["memory_misses"])
		info += fmt.Sprintf("ssd_hits:%d\r\n", stats["ssd_hits"])
		info += fmt.Sprintf("ssd_misses:%d\r\n", stats["ssd_misses"])
		info += fmt.Sprintf("evictions:%d\r\n", stats["evictions"])
		info += fmt.Sprintf("memory_entries:%d\r\n", stats["memory_entries"])
		info += fmt.Sprintf("memory_bytes:%d\r\n", stats["memory_bytes"])
		info += fmt.Sprintf("memory_hit_rate:%.4f\r\n", stats["memory_hit_rate"])
		info += fmt.Sprintf("ssd_hit_rate:%.4f\r\n", stats["ssd_hit_rate"])

		return formatBulkString([]byte(info))

	case "QUIT":
		return okResponse

	default:
		return errorResponse
	}
}

// parseSimpleInt parses a simple integer (optimized for common cases)
func parseSimpleInt(s string) int {
	if len(s) == 0 {
		return 0
	}

	result := 0
	for i := 0; i < len(s); i++ {
		if s[i] >= '0' && s[i] <= '9' {
			result = result*10 + int(s[i]-'0')
		} else {
			return 0
		}
	}
	return result
}

// NewUltraHybridServer creates a new ultra hybrid server
func NewUltraHybridServer(address string, port int, cacheConfig *cache.HybridCacheConfig) (*UltraHybridServer, error) {
	// Create hybrid cache
	hybridCache, err := cache.NewHybridCache(cacheConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create hybrid cache: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())

	server := &UltraHybridServer{
		address:        address,
		port:           port,
		cache:          hybridCache,
		cacheConfig:    cacheConfig,
		maxConnections: 2000,
		bufferSize:     65536, // 64KB buffers
		gcPercent:      20,    // Aggressive GC tuning
		ctx:            ctx,
		cancel:         cancel,
		stats: &ServerStats{
			startTime: time.Now(),
		},
	}

	return server, nil
}

// Start starts the ultra hybrid server
func (s *UltraHybridServer) Start() error {
	// Set GC target
	debug.SetGCPercent(s.gcPercent)

	// Create listener with optimizations
	lc := &net.ListenConfig{
		Control: func(network, address string, c syscall.RawConn) error {
			return c.Control(func(fd uintptr) {
				syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1)
				syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_REUSEPORT, 1)
				syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_RCVBUF, s.bufferSize)
				syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_SNDBUF, s.bufferSize)
			})
		},
	}

	listener, err := lc.Listen(s.ctx, "tcp", fmt.Sprintf("%s:%d", s.address, s.port))
	if err != nil {
		return fmt.Errorf("failed to create listener: %w", err)
	}

	s.listener = listener

	// Start metrics worker
	s.wg.Add(1)
	go s.metricsWorker()

	fmt.Printf("🚀 Ultra Hybrid Meteor server listening on %s:%d\n", s.address, s.port)

	// Display cache configuration
	if s.cacheConfig.TieredPrefix != "" {
		fmt.Printf("✅ Hybrid cache enabled (Memory + SSD overflow)\n")
		fmt.Printf("💾 SSD storage: %s\n", s.cacheConfig.TieredPrefix)
	} else {
		fmt.Printf("✅ Pure in-memory cache enabled (high performance)\n")
		fmt.Printf("💾 Storage: Memory-only\n")
	}

	fmt.Printf("✅ Zero-copy RESP parsing enabled\n")
	fmt.Printf("✅ TCP optimizations enabled\n")
	fmt.Printf("✅ Ultra-fast command processing\n")
	fmt.Printf("📊 Buffer size: %d bytes\n", s.bufferSize)
	fmt.Printf("🔧 Max connections: %d\n", s.maxConnections)
	fmt.Printf("🧠 Memory limit: %d MB (%d entries)\n", s.cacheConfig.MaxMemoryBytes/(1024*1024), s.cacheConfig.MaxMemoryEntries)
	fmt.Printf("⚡ GC target: %d%%\n", s.gcPercent)
	fmt.Printf("🏃 Ready to serve Redis clients!\n")

	// Accept connections
	for {
		select {
		case <-s.ctx.Done():
			return nil
		default:
			conn, err := listener.Accept()
			if err != nil {
				if s.ctx.Err() != nil {
					return nil
				}
				continue
			}

			// Check connection limit
			if atomic.LoadInt64(&s.stats.currentConnections) >= int64(s.maxConnections) {
				conn.Close()
				continue
			}

			atomic.AddInt64(&s.stats.totalConnections, 1)
			go s.handleConnection(conn)
		}
	}
}

// metricsWorker periodically prints server metrics
func (s *UltraHybridServer) metricsWorker() {
	defer s.wg.Done()

	ticker := time.NewTicker(time.Second * 10)
	defer ticker.Stop()

	lastCommands := int64(0)
	lastTime := time.Now()

	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			now := time.Now()
			currentCommands := atomic.LoadInt64(&s.stats.totalCommands)

			// Calculate commands per second
			if now.Sub(lastTime).Seconds() > 0 {
				s.stats.commandsPerSecond = float64(currentCommands-lastCommands) / now.Sub(lastTime).Seconds()
			}

			lastCommands = currentCommands
			lastTime = now

			// Print metrics
			fmt.Printf("📊 Metrics: Connections=%d, Commands=%d, Errors=%d, CPS=%.2f, Uptime=%v\n",
				atomic.LoadInt64(&s.stats.currentConnections),
				atomic.LoadInt64(&s.stats.totalCommands),
				atomic.LoadInt64(&s.stats.totalErrors),
				s.stats.commandsPerSecond,
				now.Sub(s.stats.startTime).Truncate(time.Second),
			)
		}
	}
}

// Stop stops the ultra hybrid server
func (s *UltraHybridServer) Stop() error {
	s.cancel()

	if s.listener != nil {
		s.listener.Close()
	}

	// Close all connections
	s.connections.Range(func(key, value interface{}) bool {
		if conn, ok := value.(net.Conn); ok {
			conn.Close()
		}
		return true
	})

	s.wg.Wait()

	// Close cache
	if err := s.cache.Close(); err != nil {
		return fmt.Errorf("failed to close cache: %w", err)
	}

	// Print final stats
	fmt.Printf("📊 Final stats:\n")
	fmt.Printf("  total_connections: %d\n", atomic.LoadInt64(&s.stats.totalConnections))
	fmt.Printf("  total_commands: %d\n", atomic.LoadInt64(&s.stats.totalCommands))
	fmt.Printf("  total_errors: %d\n", atomic.LoadInt64(&s.stats.totalErrors))
	fmt.Printf("  commands_per_second: %.2f\n", s.stats.commandsPerSecond)
	fmt.Printf("  uptime_seconds: %.2f\n", time.Since(s.stats.startTime).Seconds())
	fmt.Printf("  goroutines: %d\n", runtime.NumGoroutine())

	cacheStats := s.cache.GetStats()
	fmt.Printf("  cache_memory_hits: %d\n", cacheStats["memory_hits"])
	fmt.Printf("  cache_memory_misses: %d\n", cacheStats["memory_misses"])
	fmt.Printf("  cache_ssd_hits: %d\n", cacheStats["ssd_hits"])
	fmt.Printf("  cache_ssd_misses: %d\n", cacheStats["ssd_misses"])
	fmt.Printf("  cache_evictions: %d\n", cacheStats["evictions"])
	fmt.Printf("  cache_memory_entries: %d\n", cacheStats["memory_entries"])
	fmt.Printf("  cache_memory_bytes: %d\n", cacheStats["memory_bytes"])
	fmt.Printf("  memory_hit_rate: %.4f\n", cacheStats["memory_hit_rate"])
	fmt.Printf("  ssd_hit_rate: %.4f\n", cacheStats["ssd_hit_rate"])

	fmt.Printf("🎯 Ultra Hybrid server stopped\n")
	return nil
}

func main() {
	var (
		address = flag.String("address", "localhost", "Server address")
		port    = flag.Int("port", 6380, "Server port")

		// Cache configuration
		maxMemoryEntries = flag.Int("max-memory-entries", 100000, "Maximum entries in memory cache")
		maxMemoryBytes   = flag.Int64("max-memory-bytes", 256*1024*1024, "Maximum memory usage in bytes")
		tieredPrefix     = flag.String("tiered-prefix", "", "Tiered storage directory prefix (empty = pure in-memory)")
		ssdPageSize      = flag.Int("ssd-page-size", 4096, "SSD page size")
		ssdMaxFileSize   = flag.Int64("ssd-max-file-size", 2*1024*1024*1024, "Maximum SSD file size")

		// Performance tuning
		evictionInterval = flag.Duration("eviction-interval", time.Second*30, "Cache eviction interval")
		metricsInterval  = flag.Duration("metrics-interval", time.Second*10, "Metrics reporting interval")
		defaultTTL       = flag.Duration("default-ttl", time.Hour, "Default TTL for cache entries")
	)
	flag.Parse()

	// Create cache configuration
	cacheConfig := &cache.HybridCacheConfig{
		MaxMemoryEntries: *maxMemoryEntries,
		MaxMemoryBytes:   *maxMemoryBytes,
		TieredPrefix:     *tieredPrefix,
		SSDPageSize:      *ssdPageSize,
		SSDMaxFileSize:   *ssdMaxFileSize,
		EvictionInterval: *evictionInterval,
		MetricsInterval:  *metricsInterval,
		DefaultTTL:       *defaultTTL,
	}

	// Create and start server
	server, err := NewUltraHybridServer(*address, *port, cacheConfig)
	if err != nil {
		log.Fatalf("Failed to create server: %v", err)
	}

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		fmt.Println("\nShutdown signal received, stopping server...")
		server.Stop()
		os.Exit(0)
	}()

	// Start server
	if err := server.Start(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
