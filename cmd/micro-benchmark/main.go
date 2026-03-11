package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"runtime"
	"runtime/pprof"
	"sync"
	"sync/atomic"
	"time"
)

// SimpleRESPParser is a minimal RESP parser for benchmarking
type SimpleRESPParser struct {
	reader *bufio.Reader
}

func NewSimpleRESPParser(r io.Reader) *SimpleRESPParser {
	return &SimpleRESPParser{
		reader: bufio.NewReaderSize(r, 32*1024),
	}
}

func (p *SimpleRESPParser) ReadCommand() ([]string, error) {
	// Read array length
	line, err := p.reader.ReadString('\n')
	if err != nil {
		return nil, err
	}

	if len(line) < 3 || line[0] != '*' {
		return nil, fmt.Errorf("invalid array")
	}

	// Parse array length
	length := 0
	for i := 1; i < len(line)-2; i++ {
		if line[i] >= '0' && line[i] <= '9' {
			length = length*10 + int(line[i]-'0')
		}
	}

	// Read array elements
	args := make([]string, length)
	for i := 0; i < length; i++ {
		// Read bulk string length
		lengthLine, err := p.reader.ReadString('\n')
		if err != nil {
			return nil, err
		}

		if len(lengthLine) < 3 || lengthLine[0] != '$' {
			return nil, fmt.Errorf("invalid bulk string")
		}

		// Parse bulk string length
		strLength := 0
		for j := 1; j < len(lengthLine)-2; j++ {
			if lengthLine[j] >= '0' && lengthLine[j] <= '9' {
				strLength = strLength*10 + int(lengthLine[j]-'0')
			}
		}

		// Read bulk string data
		data := make([]byte, strLength)
		_, err = io.ReadFull(p.reader, data)
		if err != nil {
			return nil, err
		}

		// Read \r\n
		p.reader.ReadByte()
		p.reader.ReadByte()

		args[i] = string(data)
	}

	return args, nil
}

// SimpleRESPWriter is a minimal RESP writer for benchmarking
type SimpleRESPWriter struct {
	writer *bufio.Writer
}

func NewSimpleRESPWriter(w io.Writer) *SimpleRESPWriter {
	return &SimpleRESPWriter{
		writer: bufio.NewWriterSize(w, 32*1024),
	}
}

func (w *SimpleRESPWriter) WriteOK() error {
	_, err := w.writer.WriteString("+OK\r\n")
	return err
}

func (w *SimpleRESPWriter) WriteString(s string) error {
	_, err := w.writer.WriteString(fmt.Sprintf("$%d\r\n%s\r\n", len(s), s))
	return err
}

func (w *SimpleRESPWriter) WriteNull() error {
	_, err := w.writer.WriteString("$-1\r\n")
	return err
}

func (w *SimpleRESPWriter) WriteError(msg string) error {
	_, err := w.writer.WriteString(fmt.Sprintf("-ERR %s\r\n", msg))
	return err
}

func (w *SimpleRESPWriter) Flush() error {
	return w.writer.Flush()
}

// SimpleCache is a minimal in-memory cache for benchmarking
type SimpleCache struct {
	mu   sync.RWMutex
	data map[string]string
}

func NewSimpleCache() *SimpleCache {
	return &SimpleCache{
		data: make(map[string]string),
	}
}

func (c *SimpleCache) Get(key string) (string, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	val, exists := c.data[key]
	return val, exists
}

func (c *SimpleCache) Set(key, value string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.data[key] = value
}

func (c *SimpleCache) Delete(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.data, key)
}

// MicroServer is a minimal Redis-compatible server for benchmarking
type MicroServer struct {
	host        string
	port        int
	listener    net.Listener
	cache       *SimpleCache
	done        chan struct{}
	wg          sync.WaitGroup
	connections int64
	commands    int64
	errors      int64
	startTime   time.Time
}

func NewMicroServer(host string, port int) *MicroServer {
	return &MicroServer{
		host:      host,
		port:      port,
		cache:     NewSimpleCache(),
		done:      make(chan struct{}),
		startTime: time.Now(),
	}
}

func (s *MicroServer) Start() error {
	var err error
	s.listener, err = net.Listen("tcp", fmt.Sprintf("%s:%d", s.host, s.port))
	if err != nil {
		return err
	}

	fmt.Printf("Micro server listening on %s:%d\n", s.host, s.port)

	s.wg.Add(1)
	go s.acceptLoop()

	return nil
}

func (s *MicroServer) Stop() error {
	close(s.done)
	if s.listener != nil {
		s.listener.Close()
	}
	s.wg.Wait()
	return nil
}

func (s *MicroServer) acceptLoop() {
	defer s.wg.Done()

	for {
		conn, err := s.listener.Accept()
		if err != nil {
			select {
			case <-s.done:
				return
			default:
				continue
			}
		}

		atomic.AddInt64(&s.connections, 1)

		s.wg.Add(1)
		go s.handleConnection(conn)
	}
}

func (s *MicroServer) handleConnection(conn net.Conn) {
	defer s.wg.Done()
	defer conn.Close()
	defer atomic.AddInt64(&s.connections, -1)

	// Enable TCP_NODELAY for low latency
	if tcpConn, ok := conn.(*net.TCPConn); ok {
		tcpConn.SetNoDelay(true)
	}

	parser := NewSimpleRESPParser(conn)
	writer := NewSimpleRESPWriter(conn)

	for {
		select {
		case <-s.done:
			return
		default:
			args, err := parser.ReadCommand()
			if err != nil {
				if err == io.EOF {
					return
				}
				atomic.AddInt64(&s.errors, 1)
				writer.WriteError(err.Error())
				writer.Flush()
				continue
			}

			if len(args) == 0 {
				continue
			}

			atomic.AddInt64(&s.commands, 1)

			switch args[0] {
			case "PING":
				writer.WriteOK()
			case "GET":
				if len(args) != 2 {
					writer.WriteError("wrong number of arguments")
				} else {
					if value, exists := s.cache.Get(args[1]); exists {
						writer.WriteString(value)
					} else {
						writer.WriteNull()
					}
				}
			case "SET":
				if len(args) != 3 {
					writer.WriteError("wrong number of arguments")
				} else {
					s.cache.Set(args[1], args[2])
					writer.WriteOK()
				}
			case "DEL":
				if len(args) != 2 {
					writer.WriteError("wrong number of arguments")
				} else {
					s.cache.Delete(args[1])
					writer.WriteOK()
				}
			case "QUIT":
				writer.WriteOK()
				writer.Flush()
				return
			default:
				writer.WriteError(fmt.Sprintf("unknown command: %s", args[0]))
			}

			writer.Flush()
		}
	}
}

func (s *MicroServer) GetStats() map[string]interface{} {
	uptime := time.Since(s.startTime)
	cmds := atomic.LoadInt64(&s.commands)

	return map[string]interface{}{
		"uptime_seconds":      uptime.Seconds(),
		"connections":         atomic.LoadInt64(&s.connections),
		"total_commands":      cmds,
		"total_errors":        atomic.LoadInt64(&s.errors),
		"commands_per_second": float64(cmds) / uptime.Seconds(),
		"goroutines":          runtime.NumGoroutine(),
	}
}

func main() {
	// Enable CPU profiling
	f, err := os.Create("meteor-micro.prof")
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	if err := pprof.StartCPUProfile(f); err != nil {
		log.Fatal(err)
	}
	defer pprof.StopCPUProfile()

	// Set GC target for performance
	runtime.GC()

	server := NewMicroServer("localhost", 6380)

	if err := server.Start(); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}

	// Run for 30 seconds
	time.Sleep(30 * time.Second)

	stats := server.GetStats()
	fmt.Printf("Final stats:\n")
	for key, value := range stats {
		fmt.Printf("  %s: %v\n", key, value)
	}

	server.Stop()
}
