package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"syscall"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
	"github.com/kumar-sumit/meteor/pkg/server"
)

func main() {
	// Parse command line flags
	var (
		host           = flag.String("host", "localhost", "Server host")
		port           = flag.Int("port", 6379, "Server port")
		cacheDir       = flag.String("cache-dir", "/tmp/meteor-cache", "Cache directory")
		maxMemory      = flag.Int("max-memory", 10000, "Maximum memory cache entries")
		ttl            = flag.Duration("ttl", 2*time.Hour, "Default TTL for entries")
		pageSize       = flag.Int("page-size", 4096, "Storage page size")
		maxFileSize    = flag.Int64("max-file-size", 2*1024*1024*1024, "Maximum file size")
		maxConnections = flag.Int("max-connections", 1000, "Maximum concurrent connections")
		workerPoolSize = flag.Int("worker-pool-size", runtime.NumCPU()*2, "Worker pool size")
		enableLogging  = flag.Bool("enable-logging", false, "Enable verbose logging")
		bufferSize     = flag.Int("buffer-size", 64*1024, "I/O buffer size")
		pipelineSize   = flag.Int("pipeline-size", 16, "Maximum pipeline size")
		readTimeout    = flag.Duration("read-timeout", 30*time.Second, "Read timeout")
		writeTimeout   = flag.Duration("write-timeout", 30*time.Second, "Write timeout")
		idleTimeout    = flag.Duration("idle-timeout", 5*time.Minute, "Idle connection timeout")
		useOptimized   = flag.Bool("use-optimized", true, "Use optimized zero-copy server")
		gcPercent      = flag.Int("gc-percent", 50, "GC target percentage")
		maxProcs       = flag.Int("max-procs", runtime.NumCPU(), "Maximum OS threads")
		memoryLimit    = flag.Int64("memory-limit", 0, "Memory limit in bytes (0 = no limit)")
	)
	flag.Parse()

	// Set runtime optimizations
	runtime.GOMAXPROCS(*maxProcs)
	debug.SetGCPercent(*gcPercent)

	if *memoryLimit > 0 {
		debug.SetMemoryLimit(*memoryLimit)
	}

	// Print startup banner
	fmt.Printf(`
███╗   ███╗███████╗████████╗███████╗ ██████╗ ██████╗ 
████╗ ████║██╔════╝╚══██╔══╝██╔════╝██╔═══██╗██╔══██╗
██╔████╔██║█████╗     ██║   █████╗  ██║   ██║██████╔╝
██║╚██╔╝██║██╔══╝     ██║   ██╔══╝  ██║   ██║██╔══██╗
██║ ╚═╝ ██║███████╗   ██║   ███████╗╚██████╔╝██║  ██║
╚═╝     ╚═╝╚══════╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝
                                                      
   Redis-Compatible Ultra-High-Performance Cache     
                   Version 2.0.0                     
              Zero-Copy + Memory Optimized           
`)

	if *enableLogging {
		log.Printf("Starting Meteor server...")
		log.Printf("Cache directory: %s", *cacheDir)
		log.Printf("Memory entries: %d", *maxMemory)
		log.Printf("Default TTL: %v", *ttl)
		log.Printf("Page size: %d", *pageSize)
		log.Printf("Max file size: %d", *maxFileSize)
		log.Printf("Max connections: %d", *maxConnections)
		log.Printf("Worker pool size: %d", *workerPoolSize)
		log.Printf("Buffer size: %d", *bufferSize)
		log.Printf("Pipeline size: %d", *pipelineSize)
		log.Printf("Using optimized server: %v", *useOptimized)
		log.Printf("GC percent: %d", *gcPercent)
		log.Printf("Max procs: %d", *maxProcs)
		log.Printf("Memory limit: %d bytes", *memoryLimit)
	}

	// Create cache configuration
	cacheConfig := &cache.Config{
		BaseDir:          *cacheDir,
		MaxMemoryEntries: *maxMemory,
		EntryTTL:         *ttl,
		PageSize:         *pageSize,
		MaxFileSize:      *maxFileSize,
	}

	// Create cache instance
	cacheInstance, err := cache.NewOptimizedSSDCache(cacheConfig)
	if err != nil {
		log.Fatalf("Failed to create cache: %v", err)
	}
	defer cacheInstance.Close()

	// Create server configuration
	serverConfig := &server.Config{
		Host:            *host,
		Port:            *port,
		ReadTimeout:     *readTimeout,
		WriteTimeout:    *writeTimeout,
		IdleTimeout:     *idleTimeout,
		MaxConnections:  *maxConnections,
		WorkerPoolSize:  *workerPoolSize,
		EnableLogging:   *enableLogging,
		BufferSize:      *bufferSize,
		MaxPipelineSize: *pipelineSize,
	}

	// Create server instance (optimized or standard)
	var srv interface {
		Start() error
		Stop() error
		GetStats() map[string]interface{}
	}

	if *useOptimized {
		srv = server.NewOptimizedServer(serverConfig.Host, serverConfig.Port, cacheInstance, serverConfig)
		if *enableLogging {
			log.Printf("Using optimized zero-copy server")
		}
	} else {
		srv = server.NewServer(serverConfig, cacheInstance)
		if *enableLogging {
			log.Printf("Using standard server")
		}
	}

	// Start server
	if err := srv.Start(); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}

	// Start periodic cleanup if using optimized server
	if optimizedSrv, ok := srv.(*server.OptimizedServer); ok {
		// Cleanup is handled internally by the optimized server
		_ = optimizedSrv
	}

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	if *enableLogging {
		log.Printf("Server started on %s:%d", *host, *port)
		log.Printf("Press Ctrl+C to stop...")

		// Print initial stats
		stats := srv.GetStats()
		for key, value := range stats {
			log.Printf("  %s: %v", key, value)
		}
	}

	// Print performance info
	fmt.Printf("\n🚀 Meteor server started on %s:%d\n", *host, *port)
	if *useOptimized {
		fmt.Printf("✅ Zero-copy parsing enabled\n")
		fmt.Printf("✅ Memory pools enabled\n")
		fmt.Printf("✅ TCP optimizations enabled\n")
		fmt.Printf("✅ Connection pooling enabled\n")
	}
	fmt.Printf("📊 Buffer size: %d bytes\n", *bufferSize)
	fmt.Printf("🔧 Max connections: %d\n", *maxConnections)
	fmt.Printf("⚡ GC target: %d%%\n", *gcPercent)
	fmt.Printf("🏃 Ready to serve Redis clients!\n\n")

	<-sigChan

	if *enableLogging {
		log.Printf("Shutdown signal received, stopping server...")

		// Print final stats
		stats := srv.GetStats()
		log.Printf("Final stats:")
		for key, value := range stats {
			log.Printf("  %s: %v", key, value)
		}
	}

	// Create a context with timeout for shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Stop server gracefully
	done := make(chan error, 1)
	go func() {
		done <- srv.Stop()
	}()

	select {
	case err := <-done:
		if err != nil {
			log.Printf("Error during shutdown: %v", err)
		}
	case <-ctx.Done():
		log.Printf("Shutdown timeout exceeded")
	}

	if *enableLogging {
		log.Printf("Goodbye!")
	}
}
