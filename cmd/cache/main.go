package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/kumar-sumit/meteor/pkg/cache"
)

func main() {
	// Create a new cache instance with default configuration
	c, err := cache.NewSSDCache(nil)
	if err != nil {
		log.Fatalf("Failed to create cache: %v", err)
	}
	defer c.Close()

	ctx := context.Background()

	// Example: Store a value
	key := "user:123"
	value := []byte(`{"name": "John Doe", "age": 30}`)

	// Put value in cache
	if err := c.Put(ctx, key, value); err != nil {
		log.Printf("Failed to put value: %v", err)
		return
	}
	fmt.Println("Value stored successfully")

	// Get value from cache
	retrievedValue, err := c.Get(ctx, key)
	if err != nil {
		log.Printf("Failed to get value: %v", err)
		return
	}
	if retrievedValue != nil {
		fmt.Printf("Retrieved value: %s\n", string(retrievedValue))
	} else {
		fmt.Println("Value not found")
	}

	// Check if key exists
	exists, err := c.Contains(ctx, key)
	if err != nil {
		log.Printf("Failed to check if key exists: %v", err)
		return
	}
	fmt.Printf("Key exists: %v\n", exists)

	// Remove value
	if err := c.Remove(ctx, key); err != nil {
		log.Printf("Failed to remove value: %v", err)
		return
	}
	fmt.Println("Value removed successfully")

	// Wait a bit to ensure cleanup completes
	time.Sleep(time.Second)
}
