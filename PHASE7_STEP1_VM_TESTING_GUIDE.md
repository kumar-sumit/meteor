# 🚀 PHASE 7 STEP 1: VM TESTING & BENCHMARKING GUIDE

## 📋 **Current Status**

✅ **Phase 7 Step 1 Implementation**: Complete with io_uring integration  
✅ **Files Ready**: All source files and build scripts created  
⚠️ **VM Testing**: Ready for deployment once connectivity is stable  

---

## 🛠️ **Files Ready for VM Testing**

### **Source Files**
- `cpp/sharded_server_phase7_step1_iouring.cpp` - Complete io_uring server
- `cpp/build_phase7_step1_iouring.sh` - Cross-platform build script
- `cpp/sharded_server_phase6_step3_pipeline_batch.cpp` - Baseline for comparison

### **VM Setup Status**
- ✅ **memtier-benchmarking VM**: Available for building
- ✅ **mcache-ssd-tiering-poc VM**: Available for testing  
- ✅ **Phase 6 Step 3 baseline**: Built successfully on memtier-benchmarking

---

## 🔧 **VM Testing Commands (When Connectivity Restored)**

### **Step 1: Upload and Build Phase 7 Step 1**
```bash
# Upload files to memtier-benchmarking
gcloud compute scp \
    cpp/sharded_server_phase7_step1_iouring.cpp \
    cpp/build_phase7_step1_iouring.sh \
    memtier-benchmarking:/dev/shm/ \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap

# Build on VM (with io_uring support detection)
gcloud compute ssh memtier-benchmarking \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap \
    --command "
        cd /dev/shm && 
        chmod +x build_phase7_step1_iouring.sh && 
        ./build_phase7_step1_iouring.sh
    "
```

### **Step 2: Start Baseline Server (Phase 6 Step 3)**
```bash
# Start baseline for comparison
gcloud compute ssh memtier-benchmarking \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap \
    --command "
        cd /dev/shm && 
        screen -S meteor-baseline -dm ./meteor_phase6_step3_baseline -h 0.0.0.0 -p 6404 -c 4 -s 8 &&
        sleep 3 &&
        echo 'Baseline server started on port 6404'
    "
```

### **Step 3: Start Phase 7 Step 1 Server**
```bash
# Start Phase 7 Step 1 server
gcloud compute ssh memtier-benchmarking \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap \
    --command "
        cd /dev/shm && 
        screen -S meteor-p7s1 -dm ./meteor_phase7_step1_iouring -h 0.0.0.0 -p 6405 -c 4 -s 8 &&
        sleep 3 &&
        echo 'Phase 7 Step 1 server started on port 6405'
    "
```

---

## 📊 **Comprehensive Benchmark Suite**

### **Benchmark 1: Basic Functionality Test**
```bash
gcloud compute ssh memtier-benchmarking \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap \
    --command "
        echo '=== BASIC FUNCTIONALITY TEST ===' &&
        echo 'Phase 6 Step 3 Baseline:' &&
        redis-benchmark -h 127.0.0.1 -p 6404 -t set,get -n 10000 -c 10 -q &&
        echo &&
        echo 'Phase 7 Step 1 (io_uring):' &&
        redis-benchmark -h 127.0.0.1 -p 6405 -t set,get -n 10000 -c 10 -q
    "
```

### **Benchmark 2: Performance Comparison**
```bash
gcloud compute ssh memtier-benchmarking \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap \
    --command "
        echo '=== PERFORMANCE COMPARISON TEST ===' &&
        echo 'Phase 6 Step 3 Baseline (50K ops):' &&
        redis-benchmark -h 127.0.0.1 -p 6404 -t set,get -n 50000 -c 20 -P 10 -q &&
        echo &&
        echo 'Phase 7 Step 1 io_uring (50K ops):' &&
        redis-benchmark -h 127.0.0.1 -p 6405 -t set,get -n 50000 -c 20 -P 10 -q &&
        echo &&
        echo '=== EXPECTED: 3x improvement in Phase 7 Step 1 ==='
    "
```

### **Benchmark 3: Pipeline Performance**
```bash
gcloud compute ssh memtier-benchmarking \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap \
    --command "
        echo '=== PIPELINE PERFORMANCE TEST ===' &&
        echo 'Phase 6 Step 3 Baseline (memtier):' &&
        timeout 15s memtier_benchmark -s 127.0.0.1 -p 6404 --test-time=10 -t 4 -c 10 --pipeline=5 --hide-histogram &&
        echo &&
        echo 'Phase 7 Step 1 io_uring (memtier):' &&
        timeout 15s memtier_benchmark -s 127.0.0.1 -p 6405 --test-time=10 -t 4 -c 10 --pipeline=5 --hide-histogram
    "
```

### **Benchmark 4: High-Load Stress Test**
```bash
gcloud compute ssh memtier-benchmarking \
    --zone "asia-southeast1-a" \
    --project "<your-gcp-project-id>" \
    --tunnel-through-iap \
    --command "
        echo '=== HIGH-LOAD STRESS TEST ===' &&
        echo 'Phase 6 Step 3 Baseline:' &&
        redis-benchmark -h 127.0.0.1 -p 6404 -t set,get -n 100000 -c 50 -P 20 -q &&
        echo &&
        echo 'Phase 7 Step 1 io_uring:' &&
        redis-benchmark -h 127.0.0.1 -p 6405 -t set,get -n 100000 -c 50 -P 20 -q &&
        echo &&
        echo '=== TARGET: Phase 7 Step 1 should achieve 2.4M+ RPS ==='
    "
```

---

## 🎯 **Expected Results**

### **Phase 6 Step 3 Baseline (Current)**
- **SET**: ~800K RPS
- **GET**: ~800K RPS  
- **Latency P99**: ~85µs
- **Pipeline**: 8,160 ops/sec (memtier)

### **Phase 7 Step 1 Target (io_uring)**
- **SET**: **2.4M+ RPS** (3x improvement)
- **GET**: **2.4M+ RPS** (3x improvement)
- **Latency P99**: **~20µs** (4x better)
- **Pipeline**: **24K+ ops/sec** (3x improvement)

---

## 🔧 **Troubleshooting Guide**

### **If io_uring Build Fails**
The build script automatically falls back to epoll if io_uring isn't available:
```bash
# Check if io_uring is available
pkg-config --exists liburing && echo "io_uring available" || echo "Using epoll fallback"

# Manual build with epoll
g++ -std=c++17 -O3 -march=native -DHAS_LINUX_EPOLL -pthread -lnuma \
    sharded_server_phase7_step1_iouring.cpp -o meteor_phase7_step1_epoll
```

### **If VM Connectivity Issues**
1. Wait for stable connection
2. Use `screen` sessions for persistent operations
3. Check VM status: `gcloud compute instances list`
4. Use `--troubleshoot` flag for detailed diagnostics

### **If Disk Space Issues**
```bash
# Clean up /dev/shm
cd /dev/shm && rm -f *.log meteor_phase* && df -h /dev/shm
```

---

## 📈 **Performance Validation Checklist**

### **✅ Success Criteria**
- [ ] Phase 7 Step 1 builds successfully with io_uring
- [ ] Basic redis-benchmark operations work
- [ ] Pipeline processing functions correctly  
- [ ] Performance shows 3x improvement over baseline
- [ ] Latency shows significant reduction
- [ ] No memory leaks or stability issues

### **📊 Metrics to Capture**
- [ ] RPS (requests per second) for SET/GET
- [ ] Latency percentiles (P50, P95, P99)
- [ ] CPU utilization during benchmarks
- [ ] Memory usage patterns
- [ ] Pipeline throughput comparison

---

## 🚀 **Next Steps After Validation**

### **If Phase 7 Step 1 Succeeds (3x improvement achieved)**
1. **Document results** in performance comparison report
2. **Move to Phase 7 Step 2**: Enhanced batching and NUMA optimizations
3. **Plan Phase 8**: Fiber-based concurrency implementation

### **If io_uring Issues Encountered**
1. **Analyze specific io_uring compatibility problems**
2. **Implement incremental io_uring features**
3. **Consider alternative async I/O approaches**

### **Baseline Comparison Strategy**
Always compare against Phase 6 Step 3 to ensure:
- **No regressions** in existing functionality
- **Clear performance improvements** are measurable
- **All previous optimizations** are preserved

---

## 🎯 **Summary**

Phase 7 Step 1 is **implementation-complete** and ready for VM testing. The io_uring integration represents a **revolutionary improvement** in our I/O architecture that should deliver:

- **3x performance improvement** (2.4M+ RPS target)
- **4x latency reduction** (sub-20µs target)  
- **Better CPU efficiency** and memory utilization
- **Preserved compatibility** with all Phase 6 Step 3 features

**🚀 Ready to validate our path toward 10x DragonflyDB performance!**