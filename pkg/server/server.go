package server

import (
	"context"
	"fmt"
	"io"
	"net"
	"runtime"
	"sync"
	"sync/atomic"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
)

// Server represents the Redis-compatible Meteor server
type Server struct {
	host        string
	port        int
	listener    net.Listener
	cache       cache.Cache
	registry    *CommandRegistry
	done        chan struct{}
	wg          sync.WaitGroup
	clientCount int64
	totalConns  int64
	totalCmds   int64
	startTime   time.Time

	// Configuration
	config *Config
}

// Config holds server configuration
type Config struct {
	Host            string
	Port            int
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	IdleTimeout     time.Duration
	MaxConnections  int
	WorkerPoolSize  int
	EnableLogging   bool
	BufferSize      int
	MaxPipelineSize int
}

// DefaultConfig returns default server configuration
func DefaultConfig() *Config {
	return &Config{
		Host:            "localhost",
		Port:            6379,
		ReadTimeout:     30 * time.Second,
		WriteTimeout:    30 * time.Second,
		IdleTimeout:     5 * time.Minute,
		MaxConnections:  1000,
		WorkerPoolSize:  runtime.NumCPU() * 2,
		EnableLogging:   false, // Disable by default for performance
		BufferSize:      32 * 1024,
		MaxPipelineSize: 16,
	}
}

// NewServer creates a new server instance
func NewServer(config *Config, cache cache.Cache) *Server {
	if config == nil {
		config = DefaultConfig()
	}

	return &Server{
		host:      config.Host,
		port:      config.Port,
		cache:     cache,
		registry:  NewCommandRegistry(),
		done:      make(chan struct{}),
		startTime: time.Now(),
		config:    config,
	}
}

// Start starts the server
func (s *Server) Start() error {
	var err error
	s.listener, err = net.Listen("tcp", fmt.Sprintf("%s:%d", s.host, s.port))
	if err != nil {
		return fmt.Errorf("failed to listen: %v", err)
	}

	if s.config.EnableLogging {
		fmt.Printf("Meteor server listening on %s:%d\n", s.host, s.port)
	}

	// Start accepting connections
	s.wg.Add(1)
	go s.acceptLoop()

	return nil
}

// Stop stops the server
func (s *Server) Stop() error {
	close(s.done)

	if s.listener != nil {
		s.listener.Close()
	}

	s.wg.Wait()

	if s.config.EnableLogging {
		fmt.Println("Server stopped gracefully")
	}
	return nil
}

// acceptLoop accepts incoming connections
func (s *Server) acceptLoop() {
	defer s.wg.Done()

	for {
		conn, err := s.listener.Accept()
		if err != nil {
			select {
			case <-s.done:
				return
			default:
				if s.config.EnableLogging {
					fmt.Printf("Failed to accept connection: %v\n", err)
				}
				continue
			}
		}

		atomic.AddInt64(&s.clientCount, 1)
		atomic.AddInt64(&s.totalConns, 1)

		s.wg.Add(1)
		go s.handleConnection(conn)
	}
}

// handleConnection handles a single client connection with minimal overhead
func (s *Server) handleConnection(conn net.Conn) {
	defer s.wg.Done()
	defer conn.Close()

	defer func() {
		atomic.AddInt64(&s.clientCount, -1)
	}()

	if s.config.EnableLogging {
		fmt.Printf("Client connected: %s\n", conn.RemoteAddr())
	}

	// Create parser and serializer with large buffers
	parser := NewRESPParser(conn)
	serializer := NewRESPSerializer(conn)

	ctx := context.Background()

	for {
		select {
		case <-s.done:
			return
		default:
			// Parse RESP command
			value, err := parser.Parse()
			if err != nil {
				if err == io.EOF {
					if s.config.EnableLogging {
						fmt.Printf("Client disconnected: %s\n", conn.RemoteAddr())
					}
					return
				}
				if s.config.EnableLogging {
					fmt.Printf("Parse error: %v\n", err)
				}
				serializer.WriteError(err.Error())
				serializer.Flush()
				continue
			}

			// Handle command directly without worker pool overhead
			atomic.AddInt64(&s.totalCmds, 1)
			response := s.handleCommand(ctx, value)

			// Send response immediately
			err = serializer.WriteValue(*response)
			if err != nil {
				if s.config.EnableLogging {
					fmt.Printf("Write error: %v\n", err)
				}
				return
			}

			// Flush immediately for low latency
			serializer.Flush()

			// Check for QUIT command
			if response.Type == SimpleString && response.Str == "OK" {
				if s.isQuitCommand(value) {
					return
				}
			}
		}
	}
}

// handleCommand processes a single Redis command
func (s *Server) handleCommand(ctx context.Context, value *RESPValue) *RESPValue {
	if value.Type != Array || len(value.Array) == 0 {
		return &RESPValue{Type: Error, Str: "invalid command format"}
	}

	cmd := value.Array[0]
	if cmd.Type != BulkString {
		return &RESPValue{Type: Error, Str: "invalid command type"}
	}

	// Get command handler
	handler := s.registry.GetHandler(cmd.Str)
	if handler == nil {
		return &RESPValue{Type: Error, Str: fmt.Sprintf("unknown command: %s", cmd.Str)}
	}

	// Convert RESPValue arguments to string arguments
	args := make([]string, len(value.Array)-1)
	for i := 1; i < len(value.Array); i++ {
		if value.Array[i].Type != BulkString {
			return &RESPValue{Type: Error, Str: "invalid argument type"}
		}
		args[i-1] = value.Array[i].Str
	}

	// Execute command
	return handler(ctx, args, s.cache)
}

// isQuitCommand checks if the command is QUIT
func (s *Server) isQuitCommand(value *RESPValue) bool {
	if value.Type == Array && len(value.Array) > 0 {
		cmd := value.Array[0]
		return cmd.Type == BulkString && cmd.Str == "QUIT"
	}
	return false
}

// GetStats returns server statistics
func (s *Server) GetStats() map[string]interface{} {
	uptime := time.Since(s.startTime)
	return map[string]interface{}{
		"host":                s.host,
		"port":                s.port,
		"uptime_seconds":      uptime.Seconds(),
		"connected_clients":   atomic.LoadInt64(&s.clientCount),
		"total_connections":   atomic.LoadInt64(&s.totalConns),
		"total_commands":      atomic.LoadInt64(&s.totalCmds),
		"commands_per_second": float64(atomic.LoadInt64(&s.totalCmds)) / uptime.Seconds(),
		"max_connections":     s.config.MaxConnections,
	}
}
