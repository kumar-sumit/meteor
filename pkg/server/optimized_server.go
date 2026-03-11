package server

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"runtime"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
)

// ConnectionPool manages a pool of connections for reuse with enhanced performance
type ConnectionPool struct {
	pool          chan *PooledConnection
	maxSize       int
	mu            sync.RWMutex
	count         int64
	totalCreated  int64
	totalReused   int64
	cleanupTicker *time.Ticker
	stopCleanup   chan struct{}

	// Performance optimizations
	maxIdleTime time.Duration
	prealloc    bool
	warmupSize  int
}

// PooledConnection represents a reusable connection with optimizations
type PooledConnection struct {
	conn       net.Conn
	parser     *ZeroCopyRESPParser
	serializer *ZeroCopyRESPSerializer
	lastUsed   time.Time
	id         int64

	// Performance optimizations
	tcpConn     *net.TCPConn
	readBuffer  []byte
	writeBuffer []byte
	bufferPool  *sync.Pool

	// Connection statistics
	totalCommands int64
	totalBytes    int64
	createdAt     time.Time
}

// NewConnectionPool creates a new connection pool with optimizations
func NewConnectionPool(maxSize int) *ConnectionPool {
	pool := &ConnectionPool{
		pool:          make(chan *PooledConnection, maxSize),
		maxSize:       maxSize,
		maxIdleTime:   time.Minute * 5,
		prealloc:      true,
		warmupSize:    maxSize / 4,
		cleanupTicker: time.NewTicker(time.Minute),
		stopCleanup:   make(chan struct{}),
	}

	// Start cleanup goroutine
	go pool.cleanup()

	return pool
}

// Get retrieves a connection from the pool
func (p *ConnectionPool) Get() *PooledConnection {
	select {
	case conn := <-p.pool:
		atomic.AddInt64(&p.count, -1)
		atomic.AddInt64(&p.totalReused, 1)
		return conn
	default:
		return nil
	}
}

// Put returns a connection to the pool
func (p *ConnectionPool) Put(conn *PooledConnection) {
	if conn == nil {
		return
	}

	conn.lastUsed = time.Now()

	select {
	case p.pool <- conn:
		atomic.AddInt64(&p.count, 1)
	default:
		// Pool is full, discard the connection
		conn.conn.Close()
	}
}

// cleanup periodically removes idle connections
func (p *ConnectionPool) cleanup() {
	for {
		select {
		case <-p.cleanupTicker.C:
			p.cleanupIdle()
		case <-p.stopCleanup:
			return
		}
	}
}

// cleanupIdle removes connections that have been idle too long
func (p *ConnectionPool) cleanupIdle() {
	now := time.Now()
	var toClose []*PooledConnection

	// Collect idle connections
	for {
		select {
		case conn := <-p.pool:
			if now.Sub(conn.lastUsed) > p.maxIdleTime {
				toClose = append(toClose, conn)
			} else {
				// Put back non-idle connection
				p.pool <- conn
				return
			}
		default:
			// No more connections to check
			goto cleanup
		}
	}

cleanup:
	// Close idle connections
	for _, conn := range toClose {
		conn.conn.Close()
		atomic.AddInt64(&p.count, -1)
	}
}

// Size returns the current pool size
func (p *ConnectionPool) Size() int64 {
	return atomic.LoadInt64(&p.count)
}

// Stats returns pool statistics
func (p *ConnectionPool) Stats() map[string]interface{} {
	return map[string]interface{}{
		"pool_size":     atomic.LoadInt64(&p.count),
		"max_size":      p.maxSize,
		"total_created": atomic.LoadInt64(&p.totalCreated),
		"total_reused":  atomic.LoadInt64(&p.totalReused),
		"max_idle_time": p.maxIdleTime,
	}
}

// Close closes the connection pool
func (p *ConnectionPool) Close() {
	close(p.stopCleanup)
	p.cleanupTicker.Stop()

	// Close all pooled connections
	for {
		select {
		case conn := <-p.pool:
			conn.conn.Close()
		default:
			return
		}
	}
}

// OptimizedServer represents a highly optimized Redis-compatible server
type OptimizedServer struct {
	host     string
	port     int
	listener net.Listener
	cache    cache.Cache
	registry *CommandRegistry
	done     chan struct{}
	wg       sync.WaitGroup
	config   *Config
	connPool *ConnectionPool

	// Performance metrics
	activeConns int64
	totalConns  int64
	totalCmds   int64
	totalErrors int64
	startTime   time.Time

	// TCP optimizations
	tcpNoDelay      bool
	tcpKeepAlive    bool
	keepAlivePeriod time.Duration
	readBuffer      int
	writeBuffer     int
	reusePort       bool

	// Socket optimizations
	socketOptions map[int]int

	// Connection handling optimizations
	maxConnections    int
	connectionTimeout time.Duration
	readTimeout       time.Duration
	writeTimeout      time.Duration

	// Zero-copy buffer pools
	parserPool     *sync.Pool
	serializerPool *sync.Pool
	bufferPool     *sync.Pool

	// Performance monitoring
	metrics        *ServerMetrics
	metricsEnabled bool
}

// ServerMetrics tracks server performance metrics
type ServerMetrics struct {
	ConnectionsAccepted int64
	ConnectionsRejected int64
	ConnectionsActive   int64
	CommandsProcessed   int64
	CommandsErrored     int64
	BytesRead           int64
	BytesWritten        int64
	AverageResponseTime time.Duration
	P95ResponseTime     time.Duration
	P99ResponseTime     time.Duration

	// TCP specific metrics
	TCPConnections       int64
	TCPErrors            int64
	SocketBufferOverruns int64
	KeepAliveProbes      int64

	mu sync.RWMutex
}

// NewOptimizedServer creates a new optimized server
func NewOptimizedServer(host string, port int, cache cache.Cache, config *Config) *OptimizedServer {
	maxConns := config.MaxConnections
	if maxConns == 0 {
		maxConns = 10000
	}

	server := &OptimizedServer{
		host:      host,
		port:      port,
		cache:     cache,
		registry:  NewCommandRegistry(),
		done:      make(chan struct{}),
		config:    config,
		connPool:  NewConnectionPool(maxConns / 10), // Pool size is 10% of max connections
		startTime: time.Now(),

		// TCP optimizations
		tcpNoDelay:      true,
		tcpKeepAlive:    true,
		keepAlivePeriod: time.Second * 30,
		readBuffer:      64 * 1024, // 64KB
		writeBuffer:     64 * 1024, // 64KB
		reusePort:       true,

		// Socket optimizations
		socketOptions: map[int]int{
			syscall.SO_REUSEADDR: 1,
			syscall.SO_KEEPALIVE: 1,
		},

		// Connection handling
		maxConnections:    maxConns,
		connectionTimeout: time.Second * 30,
		readTimeout:       time.Second * 30,
		writeTimeout:      time.Second * 30,

		// Performance monitoring
		metrics:        &ServerMetrics{},
		metricsEnabled: true,
	}

	// Initialize buffer pools
	server.parserPool = &sync.Pool{
		New: func() interface{} {
			return &ZeroCopyRESPParser{}
		},
	}

	server.serializerPool = &sync.Pool{
		New: func() interface{} {
			return &ZeroCopyRESPSerializer{}
		},
	}

	server.bufferPool = &sync.Pool{
		New: func() interface{} {
			return make([]byte, 0, 4096)
		},
	}

	// Add support for SO_REUSEPORT on Linux
	if runtime.GOOS == "linux" {
		server.socketOptions[0x0F] = 1 // SO_REUSEPORT
	}

	return server
}

// Start starts the optimized server
func (s *OptimizedServer) Start() error {
	// Create optimized listener
	listener, err := s.createOptimizedListener()
	if err != nil {
		return fmt.Errorf("failed to create listener: %w", err)
	}

	s.listener = listener

	// Start accepting connections
	s.wg.Add(1)
	go s.acceptLoop()

	return nil
}

// createOptimizedListener creates a listener with TCP optimizations
func (s *OptimizedServer) createOptimizedListener() (net.Listener, error) {
	// Create socket with optimizations
	fd, err := syscall.Socket(syscall.AF_INET, syscall.SOCK_STREAM, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to create socket: %w", err)
	}

	// Apply socket options
	for opt, val := range s.socketOptions {
		if err := syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, opt, val); err != nil {
			syscall.Close(fd)
			return nil, fmt.Errorf("failed to set socket option %d: %w", opt, err)
		}
	}

	// Set TCP_NODELAY
	if s.tcpNoDelay {
		if err := syscall.SetsockoptInt(fd, syscall.IPPROTO_TCP, syscall.TCP_NODELAY, 1); err != nil {
			syscall.Close(fd)
			return nil, fmt.Errorf("failed to set TCP_NODELAY: %w", err)
		}
	}

	// Set socket buffer sizes
	if err := syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_RCVBUF, s.readBuffer); err != nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("failed to set read buffer size: %w", err)
	}

	if err := syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_SNDBUF, s.writeBuffer); err != nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("failed to set write buffer size: %w", err)
	}

	// Bind to address
	addr := &syscall.SockaddrInet4{Port: s.port}
	if s.host != "" && s.host != "0.0.0.0" {
		// Handle localhost
		if s.host == "localhost" {
			copy(addr.Addr[:], []byte{127, 0, 0, 1})
		} else {
			ip := net.ParseIP(s.host)
			if ip == nil {
				syscall.Close(fd)
				return nil, fmt.Errorf("invalid host address: %s", s.host)
			}
			ipv4 := ip.To4()
			if ipv4 == nil {
				syscall.Close(fd)
				return nil, fmt.Errorf("host address is not IPv4: %s", s.host)
			}
			copy(addr.Addr[:], ipv4)
		}
	}

	if err := syscall.Bind(fd, addr); err != nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("failed to bind socket: %w", err)
	}

	// Listen with optimized backlog
	backlog := 1024
	if s.maxConnections > 0 && s.maxConnections < backlog {
		backlog = s.maxConnections
	}

	if err := syscall.Listen(fd, backlog); err != nil {
		syscall.Close(fd)
		return nil, fmt.Errorf("failed to listen: %w", err)
	}

	// Convert to net.Listener
	file := os.NewFile(uintptr(fd), "socket")
	defer file.Close()

	listener, err := net.FileListener(file)
	if err != nil {
		return nil, fmt.Errorf("failed to create listener from file: %w", err)
	}

	return listener, nil
}

// acceptLoop accepts incoming connections with optimizations
func (s *OptimizedServer) acceptLoop() {
	defer s.wg.Done()

	for {
		select {
		case <-s.done:
			return
		default:
		}

		conn, err := s.listener.Accept()
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Temporary() {
				// Temporary error, continue
				continue
			}
			// Permanent error or server shutdown
			return
		}

		// Check connection limit
		if atomic.LoadInt64(&s.activeConns) >= int64(s.maxConnections) {
			atomic.AddInt64(&s.metrics.ConnectionsRejected, 1)
			conn.Close()
			continue
		}

		// Optimize connection
		if err := s.optimizeConnection(conn); err != nil {
			conn.Close()
			continue
		}

		// Handle connection
		atomic.AddInt64(&s.activeConns, 1)
		atomic.AddInt64(&s.totalConns, 1)
		atomic.AddInt64(&s.metrics.ConnectionsAccepted, 1)

		s.wg.Add(1)
		go s.handleConnection(conn)
	}
}

// optimizeConnection applies TCP optimizations to a connection
func (s *OptimizedServer) optimizeConnection(conn net.Conn) error {
	tcpConn, ok := conn.(*net.TCPConn)
	if !ok {
		return fmt.Errorf("not a TCP connection")
	}

	// Set TCP_NODELAY
	if s.tcpNoDelay {
		if err := tcpConn.SetNoDelay(true); err != nil {
			return fmt.Errorf("failed to set TCP_NODELAY: %w", err)
		}
	}

	// Set keep-alive
	if s.tcpKeepAlive {
		if err := tcpConn.SetKeepAlive(true); err != nil {
			return fmt.Errorf("failed to set keep-alive: %w", err)
		}

		if err := tcpConn.SetKeepAlivePeriod(s.keepAlivePeriod); err != nil {
			return fmt.Errorf("failed to set keep-alive period: %w", err)
		}
	}

	// Set timeouts
	if s.readTimeout > 0 {
		if err := conn.SetReadDeadline(time.Now().Add(s.readTimeout)); err != nil {
			return fmt.Errorf("failed to set read timeout: %w", err)
		}
	}

	if s.writeTimeout > 0 {
		if err := conn.SetWriteDeadline(time.Now().Add(s.writeTimeout)); err != nil {
			return fmt.Errorf("failed to set write timeout: %w", err)
		}
	}

	return nil
}

// handleConnection handles a single connection with optimizations
func (s *OptimizedServer) handleConnection(conn net.Conn) {
	defer func() {
		conn.Close()
		atomic.AddInt64(&s.activeConns, -1)
		s.wg.Done()
	}()

	// Try to get pooled connection wrapper
	pooledConn := s.connPool.Get()
	if pooledConn == nil {
		// Create new connection wrapper
		pooledConn = &PooledConnection{
			conn:        conn,
			parser:      NewZeroCopyRESPParser(conn),
			serializer:  NewZeroCopyRESPSerializer(conn),
			id:          atomic.AddInt64(&s.totalConns, 1),
			readBuffer:  make([]byte, s.readBuffer),
			writeBuffer: make([]byte, s.writeBuffer),
			bufferPool:  s.bufferPool,
			createdAt:   time.Now(),
		}

		// Set TCP connection reference
		if tcpConn, ok := conn.(*net.TCPConn); ok {
			pooledConn.tcpConn = tcpConn
		}

		atomic.AddInt64(&s.connPool.totalCreated, 1)
	} else {
		// Reuse existing connection wrapper
		pooledConn.conn = conn
		pooledConn.parser = NewZeroCopyRESPParser(conn)
		pooledConn.serializer = NewZeroCopyRESPSerializer(conn)
	}

	// Handle commands
	s.handleCommands(pooledConn)

	// Return to pool if still valid
	if s.isConnectionValid(pooledConn) {
		s.connPool.Put(pooledConn)
	}
}

// isConnectionValid checks if a connection is still valid for pooling
func (s *OptimizedServer) isConnectionValid(conn *PooledConnection) bool {
	// Check if connection is still open
	if conn.conn == nil {
		return false
	}

	// Check connection age
	if time.Since(conn.createdAt) > time.Hour {
		return false
	}

	// Check command count
	if atomic.LoadInt64(&conn.totalCommands) > 10000 {
		return false
	}

	return true
}

// handleCommands processes commands from a connection
func (s *OptimizedServer) handleCommands(conn *PooledConnection) {
	for {
		select {
		case <-s.done:
			return
		default:
		}

		// Parse command with timeout
		start := time.Now()

		// Reset timeouts for each command
		if s.readTimeout > 0 {
			conn.conn.SetReadDeadline(time.Now().Add(s.readTimeout))
		}
		if s.writeTimeout > 0 {
			conn.conn.SetWriteDeadline(time.Now().Add(s.writeTimeout))
		}

		value, err := conn.parser.Parse()
		if err != nil {
			if err == io.EOF {
				return
			}
			atomic.AddInt64(&s.totalErrors, 1)
			atomic.AddInt64(&s.metrics.CommandsErrored, 1)

			// Send error response
			conn.serializer.WriteError(fmt.Sprintf("Parse error: %v", err))
			continue
		}

		// Process command
		s.processCommand(conn, value)

		// Update metrics
		atomic.AddInt64(&s.totalCmds, 1)
		atomic.AddInt64(&conn.totalCommands, 1)
		atomic.AddInt64(&s.metrics.CommandsProcessed, 1)

		// Update response time metrics
		responseTime := time.Since(start)
		s.updateResponseTimeMetrics(responseTime)

		// Clean up
		value.Release()
	}
}

// processCommand processes a single command
func (s *OptimizedServer) processCommand(conn *PooledConnection, value *ZeroCopyRESPValue) {
	if value.Type != Array || len(value.Array) == 0 {
		conn.serializer.WriteError("ERR Protocol error: expected array")
		return
	}

	// Extract command name
	cmdName := value.Array[0].StringUnsafe()

	// Get command handler
	handler := s.registry.GetHandler(cmdName)
	if handler == nil {
		conn.serializer.WriteError(fmt.Sprintf("ERR unknown command '%s'", cmdName))
		return
	}

	// Convert arguments to strings
	args := make([]string, len(value.Array)-1)
	for i := 1; i < len(value.Array); i++ {
		args[i-1] = value.Array[i].StringUnsafe()
	}

	// Execute command
	ctx := context.Background()
	result := handler(ctx, args, s.cache)

	// Send response
	s.sendResponse(conn, result)
}

// sendResponse sends a response to the client
func (s *OptimizedServer) sendResponse(conn *PooledConnection, response interface{}) {
	switch v := response.(type) {
	case string:
		conn.serializer.WriteSimpleString(v)
	case []byte:
		conn.serializer.WriteBulkString(v)
	case int64:
		conn.serializer.WriteInteger(v)
	case error:
		conn.serializer.WriteError(v.Error())
	case nil:
		conn.serializer.WriteNullBulkString()
	default:
		conn.serializer.WriteError("ERR Internal error")
	}
}

// updateResponseTimeMetrics updates response time statistics
func (s *OptimizedServer) updateResponseTimeMetrics(responseTime time.Duration) {
	s.metrics.mu.Lock()
	defer s.metrics.mu.Unlock()

	// Simple moving average for now
	s.metrics.AverageResponseTime = (s.metrics.AverageResponseTime + responseTime) / 2

	// Update percentiles (simplified)
	if responseTime > s.metrics.P95ResponseTime {
		s.metrics.P95ResponseTime = responseTime
	}
	if responseTime > s.metrics.P99ResponseTime {
		s.metrics.P99ResponseTime = responseTime
	}
}

// Stop stops the server
func (s *OptimizedServer) Stop() error {
	close(s.done)

	if s.listener != nil {
		s.listener.Close()
	}

	s.wg.Wait()

	if s.connPool != nil {
		s.connPool.Close()
	}

	return nil
}

// GetStats returns server metrics (for interface compatibility)
func (s *OptimizedServer) GetStats() map[string]interface{} {
	return s.GetMetrics()
}

// GetMetrics returns server metrics
func (s *OptimizedServer) GetMetrics() map[string]interface{} {
	s.metrics.mu.RLock()
	defer s.metrics.mu.RUnlock()

	return map[string]interface{}{
		"active_connections":    atomic.LoadInt64(&s.activeConns),
		"total_connections":     atomic.LoadInt64(&s.totalConns),
		"total_commands":        atomic.LoadInt64(&s.totalCmds),
		"total_errors":          atomic.LoadInt64(&s.totalErrors),
		"uptime":                time.Since(s.startTime),
		"connections_accepted":  atomic.LoadInt64(&s.metrics.ConnectionsAccepted),
		"connections_rejected":  atomic.LoadInt64(&s.metrics.ConnectionsRejected),
		"commands_processed":    atomic.LoadInt64(&s.metrics.CommandsProcessed),
		"commands_errored":      atomic.LoadInt64(&s.metrics.CommandsErrored),
		"average_response_time": s.metrics.AverageResponseTime,
		"p95_response_time":     s.metrics.P95ResponseTime,
		"p99_response_time":     s.metrics.P99ResponseTime,
		"tcp_nodelay":           s.tcpNoDelay,
		"tcp_keepalive":         s.tcpKeepAlive,
		"read_buffer_size":      s.readBuffer,
		"write_buffer_size":     s.writeBuffer,
		"connection_pool_stats": s.connPool.Stats(),
	}
}
