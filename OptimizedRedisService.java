package com.meteor.redis.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * Optimized Redis Service for High-Performance Operations
 * Uses StringRedisTemplate to avoid JSON serialization overhead and errors
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OptimizedRedisService {

    private final StringRedisTemplate stringRedisTemplate;

    /**
     * GET operation - returns raw string, no JSON parsing
     */
    public String get(String key) {
        try {
            return stringRedisTemplate.opsForValue().get(key);
        } catch (Exception e) {
            log.error("Redis GET failed for key: {}", key, e);
            return null;
        }
    }

    /**
     * SET operation - stores raw string, no JSON serialization
     */
    public void set(String key, String value) {
        try {
            stringRedisTemplate.opsForValue().set(key, value);
        } catch (Exception e) {
            log.error("Redis SET failed for key: {}, value: {}", key, value, e);
            throw e;
        }
    }

    /**
     * SET operation with TTL
     */
    public void setWithTtl(String key, String value, long timeout, TimeUnit unit) {
        try {
            stringRedisTemplate.opsForValue().set(key, value, timeout, unit);
        } catch (Exception e) {
            log.error("Redis SET with TTL failed for key: {}", key, e);
            throw e;
        }
    }

    /**
     * MSET operation - batch set multiple key-value pairs
     */
    public void setMultiple(Map<String, String> keyValueMap) {
        try {
            stringRedisTemplate.opsForValue().multiSet(keyValueMap);
        } catch (Exception e) {
            log.error("Redis MSET failed for {} keys", keyValueMap.size(), e);
            throw e;
        }
    }

    /**
     * DELETE operation
     */
    public Boolean delete(String key) {
        try {
            return stringRedisTemplate.delete(key);
        } catch (Exception e) {
            log.error("Redis DELETE failed for key: {}", key, e);
            return false;
        }
    }

    /**
     * Check if key exists
     */
    public Boolean exists(String key) {
        try {
            return stringRedisTemplate.hasKey(key);
        } catch (Exception e) {
            log.error("Redis EXISTS check failed for key: {}", key, e);
            return false;
        }
    }

    /**
     * Get TTL of key
     */
    public Long getTtl(String key) {
        try {
            return stringRedisTemplate.getExpire(key);
        } catch (Exception e) {
            log.error("Redis TTL check failed for key: {}", key, e);
            return -1L;
        }
    }
}




