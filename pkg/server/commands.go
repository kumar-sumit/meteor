package server

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
)

// CommandHandler represents a Redis command handler function
type CommandHandler func(ctx context.Context, args []string, cache cache.Cache) *RESPValue

// CommandRegistry holds all registered Redis commands
type CommandRegistry struct {
	commands map[string]CommandHandler
}

// NewCommandRegistry creates a new command registry with default Redis commands
func NewCommandRegistry() *CommandRegistry {
	registry := &CommandRegistry{
		commands: make(map[string]CommandHandler),
	}

	// Register basic Redis commands
	registry.Register("PING", handlePing)
	registry.Register("GET", handleGet)
	registry.Register("SET", handleSet)
	registry.Register("DEL", handleDel)
	registry.Register("EXISTS", handleExists)
	registry.Register("TTL", handleTTL)
	registry.Register("EXPIRE", handleExpire)
	registry.Register("KEYS", handleKeys)
	registry.Register("FLUSHALL", handleFlushAll)
	registry.Register("INFO", handleInfo)
	registry.Register("COMMAND", handleCommand)
	registry.Register("ECHO", handleEcho)
	registry.Register("QUIT", handleQuit)

	return registry
}

// Register registers a command handler
func (r *CommandRegistry) Register(command string, handler CommandHandler) {
	r.commands[strings.ToUpper(command)] = handler
}

// GetHandler returns the handler for a given command
func (r *CommandRegistry) GetHandler(command string) CommandHandler {
	return r.commands[strings.ToUpper(command)]
}

// Execute executes a Redis command
func (r *CommandRegistry) Execute(ctx context.Context, command string, args []string, cache cache.Cache) *RESPValue {
	handler, exists := r.commands[strings.ToUpper(command)]
	if !exists {
		return &RESPValue{
			Type: Error,
			Str:  fmt.Sprintf("unknown command '%s'", command),
		}
	}

	return handler(ctx, args, cache)
}

// GetCommands returns all registered commands
func (r *CommandRegistry) GetCommands() []string {
	commands := make([]string, 0, len(r.commands))
	for cmd := range r.commands {
		commands = append(commands, cmd)
	}
	return commands
}

// Command handlers

// handlePing handles PING command
func handlePing(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) == 0 {
		return &RESPValue{Type: SimpleString, Str: "PONG"}
	}
	return &RESPValue{Type: BulkString, Str: args[0]}
}

// handleGet handles GET command
func handleGet(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) != 1 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'get' command"}
	}

	key := args[0]
	value, err := cache.Get(ctx, key)
	if err != nil {
		return &RESPValue{Type: Error, Str: err.Error()}
	}

	if value == nil {
		return &RESPValue{Type: BulkString, Null: true}
	}

	return &RESPValue{Type: BulkString, Str: string(value)}
}

// handleSet handles SET command
func handleSet(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) < 2 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'set' command"}
	}

	key := args[0]
	value := []byte(args[1])

	// Parse additional SET options (EX, PX, NX, XX)
	var ttl time.Duration
	var setIfNotExists, setIfExists bool

	for i := 2; i < len(args); i++ {
		switch strings.ToUpper(args[i]) {
		case "EX":
			if i+1 >= len(args) {
				return &RESPValue{Type: Error, Str: "syntax error"}
			}
			seconds, err := strconv.Atoi(args[i+1])
			if err != nil {
				return &RESPValue{Type: Error, Str: "value is not an integer or out of range"}
			}
			ttl = time.Duration(seconds) * time.Second
			i++
		case "PX":
			if i+1 >= len(args) {
				return &RESPValue{Type: Error, Str: "syntax error"}
			}
			milliseconds, err := strconv.Atoi(args[i+1])
			if err != nil {
				return &RESPValue{Type: Error, Str: "value is not an integer or out of range"}
			}
			ttl = time.Duration(milliseconds) * time.Millisecond
			i++
		case "NX":
			setIfNotExists = true
		case "XX":
			setIfExists = true
		default:
			return &RESPValue{Type: Error, Str: "syntax error"}
		}
	}

	// Check NX/XX conditions
	if setIfNotExists || setIfExists {
		exists, err := cache.Contains(ctx, key)
		if err != nil {
			return &RESPValue{Type: Error, Str: err.Error()}
		}

		if setIfNotExists && exists {
			return &RESPValue{Type: BulkString, Null: true}
		}
		if setIfExists && !exists {
			return &RESPValue{Type: BulkString, Null: true}
		}
	}

	// Set the value
	err := cache.Put(ctx, key, value, ttl)
	if err != nil {
		return &RESPValue{Type: Error, Str: err.Error()}
	}

	return &RESPValue{Type: SimpleString, Str: "OK"}
}

// handleDel handles DEL command
func handleDel(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) == 0 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'del' command"}
	}

	deletedCount := int64(0)
	for _, key := range args {
		err := cache.Remove(ctx, key)
		if err == nil {
			deletedCount++
		}
	}

	return &RESPValue{Type: Integer, Int: deletedCount}
}

// handleExists handles EXISTS command
func handleExists(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) == 0 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'exists' command"}
	}

	existsCount := int64(0)
	for _, key := range args {
		exists, err := cache.Contains(ctx, key)
		if err == nil && exists {
			existsCount++
		}
	}

	return &RESPValue{Type: Integer, Int: existsCount}
}

// handleTTL handles TTL command
func handleTTL(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) != 1 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'ttl' command"}
	}

	key := args[0]

	// Check if key exists
	exists, err := cache.Contains(ctx, key)
	if err != nil {
		return &RESPValue{Type: Error, Str: err.Error()}
	}

	if !exists {
		return &RESPValue{Type: Integer, Int: -2} // Key doesn't exist
	}

	// For now, return -1 (no expiration) as we need to enhance cache interface
	// TODO: Implement TTL tracking in cache
	return &RESPValue{Type: Integer, Int: -1}
}

// handleExpire handles EXPIRE command
func handleExpire(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) != 2 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'expire' command"}
	}

	key := args[0]
	seconds, err := strconv.Atoi(args[1])
	if err != nil {
		return &RESPValue{Type: Error, Str: "value is not an integer or out of range"}
	}

	// Check if key exists
	value, err := cache.Get(ctx, key)
	if err != nil {
		return &RESPValue{Type: Error, Str: err.Error()}
	}

	if value == nil {
		return &RESPValue{Type: Integer, Int: 0} // Key doesn't exist
	}

	// Set with TTL
	ttl := time.Duration(seconds) * time.Second
	err = cache.Put(ctx, key, value, ttl)
	if err != nil {
		return &RESPValue{Type: Error, Str: err.Error()}
	}

	return &RESPValue{Type: Integer, Int: 1}
}

// handleKeys handles KEYS command (simple implementation)
func handleKeys(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) != 1 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'keys' command"}
	}

	// For now, return empty array as we need to enhance cache interface
	// TODO: Implement key listing in cache
	return &RESPValue{Type: Array, Array: []RESPValue{}}
}

// handleFlushAll handles FLUSHALL command
func handleFlushAll(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	err := cache.Clear(ctx)
	if err != nil {
		return &RESPValue{Type: Error, Str: err.Error()}
	}
	return &RESPValue{Type: SimpleString, Str: "OK"}
}

// handleInfo handles INFO command
func handleInfo(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	// Note: In a real implementation, we'd need access to the server instance
	// For now, we'll provide static info that matches Redis format
	info := "# Server\r\n"
	info += "meteor_version:1.0.0\r\n"
	info += "process_id:1\r\n"
	info += "tcp_port:6379\r\n"
	info += "uptime_in_seconds:1\r\n"
	info += "\r\n"
	info += "# Clients\r\n"
	info += "connected_clients:1\r\n"
	info += "\r\n"
	info += "# Memory\r\n"
	info += "used_memory:1024\r\n"
	info += "used_memory_human:1K\r\n"
	info += "\r\n"
	info += "# Stats\r\n"
	info += "total_connections_received:1\r\n"
	info += "total_commands_processed:1\r\n"
	info += "\r\n"
	info += "# Keyspace\r\n"
	info += "db0:keys=0,expires=0,avg_ttl=0\r\n"

	return &RESPValue{Type: BulkString, Str: info}
}

// handleCommand handles COMMAND command
func handleCommand(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	// Return empty array for now - Redis clients expect this
	return &RESPValue{Type: Array, Array: []RESPValue{}}
}

// handleEcho handles ECHO command
func handleEcho(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	if len(args) != 1 {
		return &RESPValue{Type: Error, Str: "wrong number of arguments for 'echo' command"}
	}

	return &RESPValue{Type: BulkString, Str: args[0]}
}

// handleQuit handles QUIT command
func handleQuit(ctx context.Context, args []string, cache cache.Cache) *RESPValue {
	return &RESPValue{Type: SimpleString, Str: "OK"}
}
