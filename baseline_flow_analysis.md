# **METEOR BASELINE FLOW ANALYSIS**

## **🚀 SINGLE GET/SET FLOW (Line-by-line trace)**

### **1. Client Request Reception:**
- **Entry Point**: `CoreThread::parse_and_submit_commands` (line 3074)
- **Command Detection**: `commands.size() == 1` → Single command path (line 3108)
- **Parsing**: `parse_single_resp_command()` → Extract command/key/value (line 3111)

### **2. Deterministic Core Routing:**
```cpp
// Line 3122: DETERMINISTIC CORE AFFINITY
size_t target_core = std::hash<std::string>{}(key) % num_cores_;

if (target_core == core_id_) {
    // LOCAL FAST PATH (line 3127)
    processor_->submit_operation(command, key, value, client_fd);
} else {
    // CROSS-CORE ROUTING (line 3131) 
    route_single_command_to_target_core(target_core, client_fd, command, key, value);
}
```

### **3. Local Processing (Same Core):**
- **submit_operation** → **execute_single_operation_optimized** (line 2275)
- **GET Flow** (line 2279): `cache_->get(key)` → `VLLHashTable::get()` → Format response
- **SET Flow** (line 2295): `cache_->set(key, value)` → `VLLHashTable::set()` → Return `+OK`

### **4. Data Storage Layer:**
- **VLLHashTable**: `std::unordered_map<std::string, Entry> data_` (line 1518)
- **Entry Structure**: `{std::string key, std::string value}` (line 1513)
- **Shared-Nothing**: Each core has complete isolated hash table

### **5. Response Generation:**
- **GET**: Zero-copy formatting via `format_get_response_direct()` (line 2284)
- **SET**: Pre-pooled `+OK\r\n` response (line 2298)
- **Direct Send**: Response sent immediately to client

---

## **🔄 PIPELINE FLOW (Multi-command coordination)**

### **1. Pipeline Detection:**
- **Entry**: `commands.size() > 1` → Pipeline path (line 3076)
- **Parsing**: All commands parsed into `std::vector<std::vector<std::string>>`

### **2. Cross-Shard Routing:**
- **Per-Command Analysis**: Each command routed individually (line 3093-3101)
- **Shard Calculation**: `hash(key) % total_shards_` then `% num_cores_`
- **ResponseTracker**: Maintains command order (line 2377-2390)

### **3. Pipeline Execution:**
- **process_pipeline_batch()**: Coordinates cross-core execution (line 2369)
- **Local Commands**: Immediate execution (line 2410)
- **Cross-Shard**: boost::fibers futures for coordination (line 2417)

### **4. Response Collection:**
- **Order Preservation**: ResponseTracker ensures correct sequence (line 2431-2448)
- **Single Response**: Combined buffer sent once (line 2456)

---

## **⚡ CRITICAL INTEGRATION POINTS FOR TTL+LRU:**

### **A. Data Storage Layer** (`VLLHashTable::Entry`):
- **Current**: `{string key, string value}`  
- **TTL Extension**: Add `expire_at`, `created_at`, `access_time` fields

### **B. Command Processing** (`execute_single_operation_optimized`):
- **GET Enhancement**: Check expiration before retrieval (line 2279)
- **SET Enhancement**: Set timestamps on storage (line 2295)
- **New Commands**: EXPIRE, TTL, PERSIST processing

### **C. Core Routing** (line 3122):
- **Extend**: Include TTL commands in deterministic routing
- **Preserve**: Zero modification to existing GET/SET routing logic

### **D. Storage Operations** (`VLLHashTable` methods):
- **get()**: Add expiration check (passive cleanup)
- **set()**: Add timestamp recording  
- **Background**: Active cleanup for expired keys

---

## **🎯 IMPLEMENTATION STRATEGY:**

1. **Phase 1**: Extend `Entry` struct with TTL fields
2. **Phase 2**: Modify `VLLHashTable` methods for TTL awareness
3. **Phase 3**: Add TTL commands to routing and processing
4. **Phase 4**: Implement background cleanup
5. **Phase 5**: Extend to pipeline flow after single flow validation

**BASELINE CORRECTNESS**: Zero modification to existing logic paths
**TTL AS OVERLAY**: Additional checks and fields, not replacement of core logic












