# Meteor Server - Redis-Compatible High-Performance Cache Server

Meteor Server is a Redis-compatible high-performance cache server that provides the speed and functionality of Redis while leveraging Meteor's optimized SSD storage backend.

## Features

- **Full Redis Protocol Compatibility**: Uses RESP (Redis Serialization Protocol)
- **High Performance**: Optimized SSD storage with async I/O
- **Redis Command Support**: GET, SET, DEL, EXISTS, TTL, PING, INFO, and more
- **TTL Support**: Automatic key expiration with EX/PX options
- **Graceful Shutdown**: Clean server shutdown with signal handling
- **Connection Management**: Concurrent client handling with proper timeouts

## Quick Start

### Build and Run

```bash
# Build the server
go build -o meteor-server cmd/server/main.go

# Run with default settings (port 6379)
./meteor-server

# Run with custom settings
./meteor-server --host 0.0.0.0 --port 6380 --cache-dir /tmp/meteor-cache
```

### Command Line Options

```bash
./meteor-server --help

  -cache-dir string
        Cache directory (default "/tmp/meteor-cache")
  -host string
        Server host (default "localhost")
  -max-file-size int
        Maximum file size (default 2147483648)
  -max-memory int
        Maximum memory cache entries (default 10000)
  -page-size int
        Storage page size (default 4096)
  -port int
        Server port (default 6379)
  -ttl duration
        Default TTL for entries (default 2h0m0s)
```

## Redis Client Compatibility

The server is fully compatible with Redis clients:

```bash
# Test with redis-cli
redis-cli -h localhost -p 6379 ping
redis-cli -h localhost -p 6379 set key "value"
redis-cli -h localhost -p 6379 get key

# Use with any Redis client library
import redis
client = redis.Redis(host='localhost', port=6379)
client.set('key', 'value')
print(client.get('key'))
```

## Supported Commands

- **Connection**: PING, QUIT, ECHO
- **String Operations**: GET, SET (with EX/PX/NX/XX), DEL
- **Key Operations**: EXISTS, TTL, EXPIRE
- **Server**: INFO, COMMAND
- **Database**: FLUSHALL
- **Utility**: KEYS (basic implementation)

## Performance Testing

Use the included test script:

```bash
./scripts/test_server.sh
```

Or use standard Redis benchmarking tools:

```bash
# Test with redis-cli
redis-cli -h localhost -p 6379 --latency-history

# Use with memtier_benchmark (if available)
memtier_benchmark --server=localhost --port=6379 --protocol=redis
```

## Architecture

The server implements a full Redis-compatible RESP protocol parser and includes:

- **RESP Parser**: Handles Redis protocol parsing and serialization
- **Command Registry**: Extensible command handling system
- **Connection Manager**: Concurrent client connection handling
- **Cache Integration**: Uses Meteor's optimized SSD cache as backend
- **Graceful Shutdown**: Clean server shutdown with connection draining

## Production Usage

The server is production-ready and can be used as a drop-in replacement for Redis in many scenarios:

1. **High-throughput applications**: Optimized for SSD storage performance
2. **Persistent caching**: Data survives server restarts
3. **Memory-efficient**: Uses disk storage with memory caching
4. **Redis migration**: Compatible with existing Redis clients

## License

Same as the parent Meteor project. 