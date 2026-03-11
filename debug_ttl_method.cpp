// **DEBUG VERSION OF TTL METHOD** - Add this to CommercialLRUCache for debugging

#include <iostream>

long ttl_debug(const std::string& key) {
    std::cerr << "[TTL DEBUG] Starting TTL check for key: '" << key << "'" << std::endl;
    
    // **SIMPLE & SAFE**: Use unique_lock to avoid deadlock-prone lock upgrades
    std::cerr << "[TTL DEBUG] Acquiring unique lock..." << std::endl;
    std::unique_lock<std::shared_mutex> lock(data_mutex_);
    std::cerr << "[TTL DEBUG] Lock acquired successfully" << std::endl;
    
    std::cerr << "[TTL DEBUG] Searching for key in data map..." << std::endl;
    auto it = data_.find(key);
    if (it == data_.end()) {
        std::cerr << "[TTL DEBUG] Key not found in data map - returning -2" << std::endl;
        return -2; // Key doesn't exist
    }
    std::cerr << "[TTL DEBUG] Key found in data map" << std::endl;
    
    // **SAFE EXPIRY CHECK**: Handle expired keys (no lock upgrade needed)
    std::cerr << "[TTL DEBUG] Checking if key is expired..." << std::endl;
    if (it->second.is_expired()) {
        std::cerr << "[TTL DEBUG] Key is expired - removing it" << std::endl;
        // Remove expired key immediately (we already have unique lock)
        update_memory_usage(key, it->second, false);
        data_.erase(it);
        std::cerr << "[TTL DEBUG] Expired key removed - returning -2" << std::endl;
        return -2; // Key was expired and removed
    }
    std::cerr << "[TTL DEBUG] Key is not expired" << std::endl;
    
    // **CRITICAL**: Check has_ttl flag for keys without TTL
    std::cerr << "[TTL DEBUG] Checking has_ttl flag: " << (it->second.has_ttl ? "true" : "false") << std::endl;
    if (!it->second.has_ttl) {
        std::cerr << "[TTL DEBUG] Key has no TTL - returning -1" << std::endl;
        return -1; // No TTL set - SHOULD RETURN -1 FOR KEYS WITHOUT TTL
    }
    
    std::cerr << "[TTL DEBUG] Key has TTL - calculating remaining time..." << std::endl;
    // Calculate remaining time for keys with TTL
    auto remaining = it->second.expiry_time - std::chrono::steady_clock::now();
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(remaining).count();
    
    std::cerr << "[TTL DEBUG] Calculated remaining seconds: " << seconds << std::endl;
    long result = std::max(0L, seconds);
    std::cerr << "[TTL DEBUG] Final result: " << result << std::endl;
    
    return result; // Return remaining seconds
}

// **SIMPLE TEST HARNESS**
void test_ttl_debug() {
    std::cerr << "\n=== TTL DEBUG TEST HARNESS ===" << std::endl;
    
    // Create test key without TTL
    std::cerr << "\n1. Creating key without TTL..." << std::endl;
    Entry test_entry("test_key", "test_value");  // This should set has_ttl = false
    std::cerr << "   Entry created with has_ttl = " << (test_entry.has_ttl ? "true" : "false") << std::endl;
    
    // Create test key with TTL  
    std::cerr << "\n2. Creating key with TTL..." << std::endl;
    Entry ttl_entry("ttl_key", "ttl_value", std::chrono::seconds(60));  // This should set has_ttl = true
    std::cerr << "   Entry created with has_ttl = " << (ttl_entry.has_ttl ? "true" : "false") << std::endl;
    
    std::cerr << "\n=== DEBUG TEST COMPLETE ===\n" << std::endl;
}

// **USAGE**: Replace regular ttl() method temporarily with ttl_debug() and call test_ttl_debug()
// This will help us see exactly what's happening during TTL execution













