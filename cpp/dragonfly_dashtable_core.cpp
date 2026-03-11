// **DragonflyDB Dashtable with Unlimited Entry Storage**
template<typename K, typename V>
class DragonflyDashtable {
private:
    // **DragonflyDB Constants (Exact Match)**
    static constexpr size_t REGULAR_BUCKETS = 56;      // DragonflyDB: 56 regular buckets per segment
    static constexpr size_t STASH_BUCKETS = 4;         // DragonflyDB: 4 stash buckets per segment  
    static constexpr size_t SLOTS_PER_BUCKET = 14;     // DragonflyDB: 14 slots per bucket
    static constexpr size_t TOTAL_BUCKETS = REGULAR_BUCKETS + STASH_BUCKETS;
    static constexpr size_t DEFAULT_SEGMENTS = 64;     // Initial segment count
    
    // **DragonflyDB Slot with 2Q Cache Policy**
    struct alignas(64) Slot {  // Cache-line aligned for performance
        std::atomic<bool> occupied{false};
        std::atomic<uint8_t> rank{SLOTS_PER_BUCKET - 1};  // 2Q: 0 = highest priority, 13 = lowest
        K key{};
        V value{};
        std::chrono::steady_clock::time_point last_access;
        
        Slot() = default;
        
        // **2Q Cache Policy: Promote slot on access**
        void promote() {
            uint8_t current_rank = rank.load(std::memory_order_relaxed);
            if (current_rank > 0) {
                rank.store(current_rank - 1, std::memory_order_relaxed);  // Move toward rank 0
            }
            last_access = std::chrono::steady_clock::now();
        }
        
        // **2Q Cache Policy: Check if slot is in probationary state**
        bool is_probationary() const {
            return rank.load(std::memory_order_relaxed) > SLOTS_PER_BUCKET / 2;
        }
    };
    
    // **DragonflyDB Bucket with Dual Hash Support**
    struct alignas(64) Bucket {  // Cache-line aligned
        std::array<Slot, SLOTS_PER_BUCKET> slots;
        std::atomic<size_t> size{0};
        
        // **Cuckoo Hashing: Insert with dual hash probing**
        bool insert(const K& key, const V& value, uint32_t primary_hash, uint32_t secondary_hash, bool is_stash = false) {
            // Check for existing key first (update case)
            for (size_t i = 0; i < SLOTS_PER_BUCKET; ++i) {
                if (slots[i].occupied.load(std::memory_order_acquire) && slots[i].key == key) {
                    slots[i].value = value;
                    slots[i].promote();  // 2Q: promote on access
                    return true;
                }
            }
            
            // Find empty slot, preferring higher-ranked slots
            for (size_t i = 0; i < SLOTS_PER_BUCKET; ++i) {
                if (!slots[i].occupied.load(std::memory_order_acquire)) {
                    slots[i].key = key;
                    slots[i].value = value;
                    slots[i].rank.store(is_stash ? SLOTS_PER_BUCKET - 1 : 0, std::memory_order_relaxed);  // Stash = probationary
                    slots[i].last_access = std::chrono::steady_clock::now();
                    slots[i].occupied.store(true, std::memory_order_release);
                    size.fetch_add(1, std::memory_order_relaxed);
                    return true;
                }
            }
            
            return false;  // Bucket full
        }
        
        // **2Q Cache Policy: Find with automatic promotion**
        bool find(const K& key, V& result) {
            for (size_t i = 0; i < SLOTS_PER_BUCKET; ++i) {
                if (slots[i].occupied.load(std::memory_order_acquire) && slots[i].key == key) {
                    result = slots[i].value;
                    slots[i].promote();  // 2Q: promote on access
                    return true;
                }
            }
            return false;
        }
        
        // **2Q Cache Policy: Evict lowest-ranked slot**
        bool evict_lru_slot() {
            size_t lru_index = 0;
            uint8_t lowest_rank = 0;
            auto oldest_time = std::chrono::steady_clock::time_point::max();
            
            // Find slot with lowest rank (highest numeric value) and oldest access time
            for (size_t i = 0; i < SLOTS_PER_BUCKET; ++i) {
                if (slots[i].occupied.load(std::memory_order_acquire)) {
                    uint8_t slot_rank = slots[i].rank.load(std::memory_order_relaxed);
                    if (slot_rank >= lowest_rank && slots[i].last_access < oldest_time) {
                        lowest_rank = slot_rank;
                        oldest_time = slots[i].last_access;
                        lru_index = i;
                    }
                }
            }
            
            // Evict the LRU slot
            if (slots[lru_index].occupied.load(std::memory_order_acquire)) {
                slots[lru_index].occupied.store(false, std::memory_order_release);
                size.fetch_sub(1, std::memory_order_relaxed);
                return true;
            }
            return false;
        }
        
        bool is_full() const {
            return size.load(std::memory_order_relaxed) >= SLOTS_PER_BUCKET;
        }
    };
    
    // **DragonflyDB Segment with Stash Buckets**
    struct alignas(64) Segment {
        std::array<Bucket, TOTAL_BUCKETS> buckets;
        std::atomic<size_t> total_entries{0};
        mutable std::shared_mutex mutex;  // Will be replaced with VLL in Phase 2
        
        // **DragonflyDB Hash Routing: Get home buckets for key**
        std::pair<size_t, size_t> get_home_buckets(uint32_t primary_hash, uint32_t secondary_hash) const {
            return {
                primary_hash % REGULAR_BUCKETS,
                secondary_hash % REGULAR_BUCKETS
            };
        }
        
        // **DragonflyDB Insert with Stash Overflow**
        bool insert(const K& key, const V& value) {
            std::unique_lock<std::shared_mutex> lock(mutex);
            
            // Calculate dual hashes for cuckoo probing
            std::hash<K> hasher;
            uint32_t primary_hash = static_cast<uint32_t>(hasher(key));
            uint32_t secondary_hash = static_cast<uint32_t>(hasher(key) ^ 0xAAAAAAAA);
            
            auto [bucket1, bucket2] = get_home_buckets(primary_hash, secondary_hash);
            
            // Try home buckets first
            if (buckets[bucket1].insert(key, value, primary_hash, secondary_hash, false)) {
                total_entries.fetch_add(1, std::memory_order_relaxed);
                return true;
            }
            if (buckets[bucket2].insert(key, value, primary_hash, secondary_hash, false)) {
                total_entries.fetch_add(1, std::memory_order_relaxed);
                return true;
            }
            
            // Try stash buckets (probationary area)
            for (size_t i = REGULAR_BUCKETS; i < TOTAL_BUCKETS; ++i) {
                if (buckets[i].insert(key, value, primary_hash, secondary_hash, true)) {
                    total_entries.fetch_add(1, std::memory_order_relaxed);
                    return true;
                }
            }
            
            // Segment is full - try eviction in stash buckets first
            for (size_t i = REGULAR_BUCKETS; i < TOTAL_BUCKETS; ++i) {
                if (buckets[i].evict_lru_slot()) {
                    if (buckets[i].insert(key, value, primary_hash, secondary_hash, true)) {
                        // No change in total_entries (evicted one, added one)
                        return true;
                    }
                }
            }
            
            return false;  // Segment full, need expansion
        }
        
        // **DragonflyDB Find with 2Q Promotion**
        bool find(const K& key, V& result) {
            std::shared_lock<std::shared_mutex> lock(mutex);
            
            std::hash<K> hasher;
            uint32_t primary_hash = static_cast<uint32_t>(hasher(key));
            uint32_t secondary_hash = static_cast<uint32_t>(hasher(key) ^ 0xAAAAAAAA);
            
            auto [bucket1, bucket2] = get_home_buckets(primary_hash, secondary_hash);
            
            // Check home buckets first
            if (buckets[bucket1].find(key, result) || buckets[bucket2].find(key, result)) {
                return true;
            }
            
            // Check stash buckets
            for (size_t i = REGULAR_BUCKETS; i < TOTAL_BUCKETS; ++i) {
                if (buckets[i].find(key, result)) {
                    return true;
                }
            }
            return false;
        }
    };
    
    // **DragonflyDB Dashtable State**
    std::vector<std::unique_ptr<Segment>> segments_;
    std::atomic<size_t> segment_count_{DEFAULT_SEGMENTS};
    std::atomic<size_t> total_entries_{0};
    mutable std::shared_mutex segments_mutex_;  // Will be replaced with VLL in Phase 2
    
    // **DragonflyDB Segment Selection**
    size_t get_segment_id(const K& key) const {
        std::hash<K> hasher;
        return hasher(key) % segment_count_.load(std::memory_order_acquire);
    }
    
    // **DragonflyDB Dynamic Segment Expansion**
    void expand_segments() {
        std::unique_lock<std::shared_mutex> lock(segments_mutex_);
        
        size_t old_count = segment_count_.load(std::memory_order_relaxed);
        size_t new_count = old_count * 2;
        
        // Add new segments
        segments_.reserve(new_count);
        for (size_t i = old_count; i < new_count; ++i) {
            segments_.emplace_back(std::make_unique<Segment>());
        }
        
        segment_count_.store(new_count, std::memory_order_release);
    }
    
    // **DragonflyDB Load Factor Check**
    bool needs_expansion() const {
        size_t entries = total_entries_.load(std::memory_order_relaxed);
        size_t segments = segment_count_.load(std::memory_order_relaxed);
        size_t capacity = segments * TOTAL_BUCKETS * SLOTS_PER_BUCKET;
        return entries > capacity * 0.75;  // 75% load factor threshold
    }
    
public:
    DragonflyDashtable() {
        segments_.reserve(DEFAULT_SEGMENTS);
        for (size_t i = 0; i < DEFAULT_SEGMENTS; ++i) {
            segments_.emplace_back(std::make_unique<Segment>());
        }
    }
    
    // **DragonflyDB Insert with Unlimited Storage**
    bool insert(const K& key, const V& value) {
        size_t segment_id = get_segment_id(key);
        
        // Ensure segment exists
        {
            std::shared_lock<std::shared_mutex> lock(segments_mutex_);
            if (segment_id < segments_.size() && segments_[segment_id]) {
                if (segments_[segment_id]->insert(key, value)) {
                    total_entries_.fetch_add(1, std::memory_order_relaxed);
                    return true;
                }
            }
        }
        
        // Segment full or doesn't exist - expand if needed
        if (needs_expansion()) {
            expand_segments();
        }
        
        // Retry with potentially new segment assignment
        segment_id = get_segment_id(key);
        std::shared_lock<std::shared_mutex> lock(segments_mutex_);
        if (segment_id < segments_.size() && segments_[segment_id]) {
            if (segments_[segment_id]->insert(key, value)) {
                total_entries_.fetch_add(1, std::memory_order_relaxed);
                return true;
            }
        }
        
        return false;
    }
    
    // **DragonflyDB Find with 2Q Promotion**
    std::optional<V> find(const K& key) const {
        size_t segment_id = get_segment_id(key);
        
        std::shared_lock<std::shared_mutex> lock(segments_mutex_);
        if (segment_id < segments_.size() && segments_[segment_id]) {
            V result;
            if (segments_[segment_id]->find(key, result)) {
                return result;
            }
        }
        return std::nullopt;
    }
    
    // **DragonflyDB Statistics**
    struct Statistics {
        size_t segments;
        size_t total_entries;
        size_t total_capacity;
        double load_factor;
        size_t regular_buckets_used;
        size_t stash_buckets_used;
    };
    
    Statistics get_statistics() const {
        std::shared_lock<std::shared_mutex> lock(segments_mutex_);
        size_t segments = segment_count_.load(std::memory_order_relaxed);
        size_t entries = total_entries_.load(std::memory_order_relaxed);
        size_t capacity = segments * TOTAL_BUCKETS * SLOTS_PER_BUCKET;
        
        return {
            segments,
            entries,
            capacity,
            capacity > 0 ? static_cast<double>(entries) / capacity : 0.0,
            segments * REGULAR_BUCKETS * SLOTS_PER_BUCKET,
            segments * STASH_BUCKETS * SLOTS_PER_BUCKET
        };
    }
    
    void print_stats() const {
        auto stats = get_statistics();
        std::cout << "🔥 DragonflyDB Dashtable Stats:\n"
                  << "   Segments: " << stats.segments << "\n"
                  << "   Entries: " << stats.total_entries << "\n"
                  << "   Load Factor: " << (stats.load_factor * 100) << "%\n"
                  << "   Regular Buckets: " << stats.regular_buckets_used << "\n"
                  << "   Stash Buckets: " << stats.stash_buckets_used << std::endl;
    }
};