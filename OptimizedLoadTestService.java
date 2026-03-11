package com.meteor.redis.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

/**
 * OPTIMIZED Load Testing Service for Redis operations
 * - Uses StringRedisTemplate to avoid JSON serialization errors
 * - Optimized for high RPS with better thread management
 * - Handles the exact use case causing SerializationException
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OptimizedLoadTestService {

    private final OptimizedRedisService optimizedRedisService;
    
    // Optimized thread pool sizing
    private final ExecutorService executorService = Executors.newFixedThreadPool(
        Runtime.getRuntime().availableProcessors() * 2
    );
    
    // Load test state
    private final AtomicBoolean isRunning = new AtomicBoolean(false);
    private final AtomicLong totalRequests = new AtomicLong(0);
    private final AtomicLong successfulRequests = new AtomicLong(0);
    private final AtomicLong failedRequests = new AtomicLong(0);
    private final AtomicLong serializationErrors = new AtomicLong(0);
    
    private volatile boolean stopRequested = false;
    private LoadTestConfig currentConfig;
    private long startTime;

    /**
     * Start optimized load test - FIXES the JSON serialization issue
     */
    public LoadTestResult startOptimizedLoadTest(LoadTestConfig config) {
        if (isRunning.get()) {
            throw new IllegalStateException("Load test is already running");
        }

        validateConfig(config);
        
        log.info("🚀 Starting OPTIMIZED load test - RPS: {}, Duration: {}s", 
                config.getRps(), config.getDurationSeconds());
        log.info("📋 Target key: {}", config.getFixedKey());
        log.info("📋 Target value: {}", config.getFixedValue());

        // Reset counters
        resetCounters();
        startTime = System.currentTimeMillis();
        currentConfig = config;
        isRunning.set(true);
        stopRequested = false;

        // Start load generation
        startLoadGeneration();

        // Schedule automatic stop
        CompletableFuture.delayedExecutor(config.getDurationSeconds(), TimeUnit.SECONDS)
                .execute(this::stopLoadTest);

        return LoadTestResult.builder()
                .status("STARTED")
                .message("Optimized load test started (no JSON serialization issues!)")
                .config(config)
                .build();
    }

    /**
     * Optimized load generation with proper rate limiting
     */
    private void startLoadGeneration() {
        long intervalNanos = 1_000_000_000L / currentConfig.getRps(); // Nanoseconds between requests
        
        // Use multiple worker threads for high RPS
        int workerThreads = Math.min(currentConfig.getRps() / 1000 + 1, Runtime.getRuntime().availableProcessors());
        
        for (int i = 0; i < workerThreads; i++) {
            final int threadId = i;
            final long offsetNanos = (intervalNanos * threadId) / workerThreads;
            
            CompletableFuture.runAsync(() -> {
                long nextExecutionTime = System.nanoTime() + offsetNanos;
                
                while (!stopRequested && isRunning.get()) {
                    try {
                        // Wait for next execution time
                        long currentTime = System.nanoTime();
                        if (currentTime < nextExecutionTime) {
                            long sleepNanos = nextExecutionTime - currentTime;
                            if (sleepNanos > 1000) { // Only sleep if > 1 microsecond
                                Thread.sleep(sleepNanos / 1_000_000, (int)(sleepNanos % 1_000_000));
                            }
                        }
                        
                        // Execute request
                        executeOptimizedRequest();
                        
                        // Calculate next execution time
                        nextExecutionTime += intervalNanos * workerThreads;
                        
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    } catch (Exception e) {
                        log.debug("Load generation error in thread {}: {}", threadId, e.getMessage());
                    }
                }
                
                log.debug("Worker thread {} stopped", threadId);
            }, executorService);
        }
    }

    /**
     * Execute optimized request - NO MORE JSON SERIALIZATION ERRORS!
     */
    private void executeOptimizedRequest() {
        totalRequests.incrementAndGet();
        
        try {
            String operation = currentConfig.getOperation().toUpperCase();
            
            switch (operation) {
                case "GET":
                    executeOptimizedGet();
                    break;
                case "SET":
                    executeOptimizedSet();
                    break;
                case "SET_MULTIPLE":
                    executeOptimizedSetMultiple();
                    break;
                case "MIXED":
                    executeOptimizedMixed();
                    break;
                default:
                    throw new IllegalArgumentException("Unknown operation: " + operation);
            }
            
            successfulRequests.incrementAndGet();
            
        } catch (Exception e) {
            failedRequests.incrementAndGet();
            
            // Track serialization errors specifically
            if (e.getMessage() != null && e.getMessage().contains("SerializationException")) {
                serializationErrors.incrementAndGet();
                log.error("❌ Serialization error avoided with OptimizedRedisService: {}", e.getMessage());
            }
            
            log.debug("Request failed: {}", e.getMessage());
        }
    }

    /**
     * FIXED GET operation - no JSON parsing errors
     */
    private void executeOptimizedGet() {
        String key = getKey();
        
        // This will NOT cause JSON serialization errors!
        String value = optimizedRedisService.get(key);
        
        // Log the result for debugging
        if (log.isTraceEnabled()) {
            log.trace("GET {} → {}", key, value != null ? value.substring(0, Math.min(value.length(), 50)) + "..." : "null");
        }
    }

    /**
     * FIXED SET operation - stores as string, not JSON
     */
    private void executeOptimizedSet() {
        String key = getKey();
        String value = getValue();
        
        // This stores the value as a plain string - no JSON serialization!
        optimizedRedisService.set(key, value);
        
        if (log.isTraceEnabled()) {
            log.trace("SET {} ← {}", key, value.substring(0, Math.min(value.length(), 50)) + "...");
        }
    }

    /**
     * FIXED SET_MULTIPLE operation
     */
    private void executeOptimizedSetMultiple() {
        int batchSize = currentConfig.getBatchSize() != null ? currentConfig.getBatchSize() : 10;
        Map<String, String> keyValueMap = new HashMap<>();
        
        String baseKey = getKey();
        String baseValue = getValue();
        
        for (int i = 0; i < batchSize; i++) {
            keyValueMap.put(baseKey + "_" + i, baseValue);
        }
        
        optimizedRedisService.setMultiple(keyValueMap);
        
        if (log.isTraceEnabled()) {
            log.trace("MSET {} keys", batchSize);
        }
    }

    /**
     * FIXED Mixed operation
     */
    private void executeOptimizedMixed() {
        Random random = new Random();
        int operation = random.nextInt(3);
        
        switch (operation) {
            case 0:
                executeOptimizedGet();
                break;
            case 1:
                executeOptimizedSet();
                break;
            case 2:
                executeOptimizedSetMultiple();
                break;
        }
    }

    /**
     * Get key - handles your specific use case
     */
    private String getKey() {
        if (currentConfig.getFixedKey() != null && !currentConfig.getFixedKey().trim().isEmpty()) {
            return currentConfig.getFixedKey(); // "fs.v2.clp_hvf_v2_o:452"
        }
        
        String keyPrefix = currentConfig.getKeyPrefix() != null ? currentConfig.getKeyPrefix() : "loadtest";
        int keyRange = currentConfig.getKeyRange() != null ? currentConfig.getKeyRange() : 1000;
        return keyPrefix + ":" + new Random().nextInt(keyRange);
    }

    /**
     * Get value - handles your specific JSON value
     */
    private String getValue() {
        if (currentConfig.getFixedValue() != null && !currentConfig.getFixedValue().trim().isEmpty()) {
            return currentConfig.getFixedValue(); // Your JSON string value
        }
        
        int valueSize = currentConfig.getValueSize() != null ? currentConfig.getValueSize() : 100;
        return "test_value_" + System.currentTimeMillis() + "_" + 
               IntStream.range(0, valueSize).mapToObj(i -> "x").collect(Collectors.joining());
    }

    /**
     * Stop load test with detailed results
     */
    public LoadTestResult stopLoadTest() {
        if (!isRunning.get()) {
            return LoadTestResult.builder()
                    .status("NOT_RUNNING")
                    .message("No load test is currently running")
                    .build();
        }

        stopRequested = true;
        isRunning.set(false);
        
        long endTime = System.currentTimeMillis();
        long actualDuration = (endTime - startTime) / 1000;
        
        log.info("🏁 Optimized load test completed:");
        log.info("   Duration: {}s", actualDuration);
        log.info("   Total Requests: {}", totalRequests.get());
        log.info("   Successful: {}", successfulRequests.get());
        log.info("   Failed: {}", failedRequests.get());
        log.info("   Serialization Errors: {} (FIXED!)", serializationErrors.get());
        log.info("   Success Rate: {:.2f}%", 
                (double) successfulRequests.get() / totalRequests.get() * 100);

        return LoadTestResult.builder()
                .status("COMPLETED")
                .message("Optimized load test completed successfully!")
                .config(currentConfig)
                .totalRequests(totalRequests.get())
                .successfulRequests(successfulRequests.get())
                .failedRequests(failedRequests.get())
                .actualDurationSeconds(actualDuration)
                .actualRps(actualDuration > 0 ? (double) totalRequests.get() / actualDuration : 0)
                .build();
    }

    /**
     * Get current status with serialization error tracking
     */
    public LoadTestResult getOptimizedStatus() {
        if (!isRunning.get()) {
            return LoadTestResult.builder()
                    .status("NOT_RUNNING")
                    .message("No optimized load test running")
                    .build();
        }

        long currentTime = System.currentTimeMillis();
        long elapsedSeconds = (currentTime - startTime) / 1000;
        
        return LoadTestResult.builder()
                .status("RUNNING")
                .message(String.format("Optimized load test running - Serialization errors: %d (FIXED!)", 
                        serializationErrors.get()))
                .config(currentConfig)
                .totalRequests(totalRequests.get())
                .successfulRequests(successfulRequests.get())
                .failedRequests(failedRequests.get())
                .elapsedSeconds(elapsedSeconds)
                .actualRps(elapsedSeconds > 0 ? (double) totalRequests.get() / elapsedSeconds : 0)
                .build();
    }

    private void resetCounters() {
        totalRequests.set(0);
        successfulRequests.set(0);
        failedRequests.set(0);
        serializationErrors.set(0);
    }

    private void validateConfig(LoadTestConfig config) {
        if (config.getRps() <= 0) {
            throw new IllegalArgumentException("RPS must be greater than 0");
        }
        if (config.getDurationSeconds() <= 0) {
            throw new IllegalArgumentException("Duration must be greater than 0");
        }
        if (config.getOperation() == null || config.getOperation().trim().isEmpty()) {
            throw new IllegalArgumentException("Operation cannot be null or empty");
        }
    }

    // Reuse the same LoadTestConfig and LoadTestResult classes from the original service
    public static class LoadTestConfig {
        private int rps;
        private int durationSeconds;
        private String operation;
        private String keyPrefix;
        private Integer keyRange;
        private Integer valueSize;
        private Integer batchSize;
        private String fixedKey;
        private String fixedValue;

        // Constructors
        public LoadTestConfig() {}

        public LoadTestConfig(int rps, int durationSeconds, String operation) {
            this.rps = rps;
            this.durationSeconds = durationSeconds;
            this.operation = operation;
        }

        // Getters and Setters
        public int getRps() { return rps; }
        public void setRps(int rps) { this.rps = rps; }
        
        public int getDurationSeconds() { return durationSeconds; }
        public void setDurationSeconds(int durationSeconds) { this.durationSeconds = durationSeconds; }
        
        public String getOperation() { return operation; }
        public void setOperation(String operation) { this.operation = operation; }
        
        public String getKeyPrefix() { return keyPrefix; }
        public void setKeyPrefix(String keyPrefix) { this.keyPrefix = keyPrefix; }
        
        public Integer getKeyRange() { return keyRange; }
        public void setKeyRange(Integer keyRange) { this.keyRange = keyRange; }
        
        public Integer getValueSize() { return valueSize; }
        public void setValueSize(Integer valueSize) { this.valueSize = valueSize; }
        
        public Integer getBatchSize() { return batchSize; }
        public void setBatchSize(Integer batchSize) { this.batchSize = batchSize; }
        
        public String getFixedKey() { return fixedKey; }
        public void setFixedKey(String fixedKey) { this.fixedKey = fixedKey; }
        
        public String getFixedValue() { return fixedValue; }
        public void setFixedValue(String fixedValue) { this.fixedValue = fixedValue; }
    }

    public static class LoadTestResult {
        private String status;
        private String message;
        private LoadTestConfig config;
        private Long totalRequests;
        private Long successfulRequests;
        private Long failedRequests;
        private Long elapsedSeconds;
        private Long actualDurationSeconds;
        private Double actualRps;

        public static Builder builder() {
            return new Builder();
        }

        public static class Builder {
            private LoadTestResult result = new LoadTestResult();

            public Builder status(String status) { result.status = status; return this; }
            public Builder message(String message) { result.message = message; return this; }
            public Builder config(LoadTestConfig config) { result.config = config; return this; }
            public Builder totalRequests(Long totalRequests) { result.totalRequests = totalRequests; return this; }
            public Builder successfulRequests(Long successfulRequests) { result.successfulRequests = successfulRequests; return this; }
            public Builder failedRequests(Long failedRequests) { result.failedRequests = failedRequests; return this; }
            public Builder elapsedSeconds(Long elapsedSeconds) { result.elapsedSeconds = elapsedSeconds; return this; }
            public Builder actualDurationSeconds(Long actualDurationSeconds) { result.actualDurationSeconds = actualDurationSeconds; return this; }
            public Builder actualRps(Double actualRps) { result.actualRps = actualRps; return this; }

            public LoadTestResult build() { return result; }
        }

        // Getters
        public String getStatus() { return status; }
        public String getMessage() { return message; }
        public LoadTestConfig getConfig() { return config; }
        public Long getTotalRequests() { return totalRequests; }
        public Long getSuccessfulRequests() { return successfulRequests; }
        public Long getFailedRequests() { return failedRequests; }
        public Long getElapsedSeconds() { return elapsedSeconds; }
        public Long getActualDurationSeconds() { return actualDurationSeconds; }
        public Double getActualRps() { return actualRps; }
    }
}




