// **CRITICAL FIX for TTL Deadlock Issue**
// Problem: TTL command hanging due to missing thread synchronization
// Solution: Add proper shared_mutex to CommercialLRUCache

// **STEP 1: Add shared_mutex to CommercialLRUCache class**
// Add this member variable to the private section of CommercialLRUCache:

private:
    mutable std::shared_mutex data_mutex_;  // Protects data_ access

// **STEP 2: Fix lazy_expire_if_needed method**
bool lazy_expire_if_needed(const std::string& key) {
    std::shared_lock<std::shared_mutex> lock(data_mutex_);
    
    auto it = data_.find(key);
    if (it != data_.end() && it->second.is_expired()) {
        // Need to upgrade to write lock for modification
        lock.unlock();
        std::unique_lock<std::shared_mutex> write_lock(data_mutex_);
        
        // Double-check after acquiring write lock (prevent race conditions)
        it = data_.find(key);
        if (it != data_.end() && it->second.is_expired()) {
            update_memory_usage(key, it->second, false);
            data_.erase(it);
            return true; // Was expired and removed
        }
    }
    return false; // Not expired or already removed
}

// **STEP 3: Fix ttl method with proper synchronization**
long ttl(const std::string& key) {
    // First attempt lazy expiry (with proper locking)
    if (lazy_expire_if_needed(key)) {
        return -2; // Key was expired and removed
    }
    
    // Now check TTL with shared lock
    std::shared_lock<std::shared_mutex> lock(data_mutex_);
    auto it = data_.find(key);
    
    if (it == data_.end()) {
        return -2; // Key doesn't exist
    }
    
    if (!it->second.has_ttl) {
        return -1; // No TTL set
    }
    
    // Calculate remaining time
    auto remaining = it->second.expiry_time - std::chrono::steady_clock::now();
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(remaining).count();
    
    return std::max(0L, seconds); // Never return negative values
}

// **STEP 4: Fix get method to be thread-safe** 
std::optional<std::string> get(const std::string& key) {
    // Lazy expiry first (already has proper locking)
    if (lazy_expire_if_needed(key)) {
        return std::nullopt; // Key was expired and removed
    }
    
    std::shared_lock<std::shared_mutex> lock(data_mutex_);
    auto it = data_.find(key);
    
    if (it == data_.end()) {
        return std::nullopt;
    }
    
    // Update LRU info (this is safe since we modify only the entry, not the map structure)
    it->second.update_access();
    return it->second.value;
}

// **STEP 5: Fix set methods to be thread-safe**
bool set(const std::string& key, const std::string& value) {
    lazy_expire_if_needed(key); // Clean up expired key if present
    
    std::unique_lock<std::shared_mutex> lock(data_mutex_);
    
    // Check memory limits
    bool is_update = data_.find(key) != data_.end();
    if (!is_update) {
        size_t estimated_size = calculate_entry_size(Entry(key, value));
        if (current_memory_usage_.load() + estimated_size > max_memory_bytes_) {
            lock.unlock(); // Release lock before calling enforce_memory_limit
            enforce_memory_limit();
            lock.lock(); // Re-acquire lock
        }
    }
    
    // Create and insert entry
    Entry entry(key, value);
    auto [it, inserted] = data_.insert_or_assign(key, entry);
    
    if (inserted) {
        update_memory_usage(key, it->second, true);
    }
    
    return true;
}

bool set_with_ttl(const std::string& key, const std::string& value, Duration ttl) {
    lazy_expire_if_needed(key); // Clean up expired key if present
    
    std::unique_lock<std::shared_mutex> lock(data_mutex_);
    
    // Check memory limits  
    bool is_update = data_.find(key) != data_.end();
    if (!is_update) {
        size_t estimated_size = calculate_entry_size(Entry(key, value, ttl));
        if (current_memory_usage_.load() + estimated_size > max_memory_bytes_) {
            lock.unlock(); // Release lock before calling enforce_memory_limit
            enforce_memory_limit();
            lock.lock(); // Re-acquire lock
        }
    }
    
    // Create entry with TTL
    Entry entry(key, value, ttl);
    auto [it, inserted] = data_.insert_or_assign(key, entry);
    
    if (inserted) {
        update_memory_usage(key, it->second, true);
    }
    
    return true;
}

// **STEP 6: Fix active_expire method**
void active_expire() {
    if (data_.empty()) return;
    
    const size_t EXPIRE_BATCH_SIZE = 20;
    size_t expired_count = 0;
    
    std::unique_lock<std::shared_mutex> lock(data_mutex_);
    
    auto it = data_.begin();
    while (it != data_.end() && expired_count < EXPIRE_BATCH_SIZE) {
        if (it->second.is_expired()) {
            update_memory_usage(it->first, it->second, false);
            it = data_.erase(it); // erase returns next iterator
            expired_count++;
        } else {
            ++it;
        }
    }
}

// **STEP 7: Fix size method**
size_t size() const {
    std::shared_lock<std::shared_mutex> lock(data_mutex_);
    return data_.size();
}
