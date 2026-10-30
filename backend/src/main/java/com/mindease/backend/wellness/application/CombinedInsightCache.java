package com.mindease.backend.wellness.application;

import java.time.Duration;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mindease.backend.wellness.dto.CombinedInsightDto;

/**
 * Short-lived Redis cache for the combined insight.
 *
 * <p>The AI call is the most expensive part of the dashboard read and the
 * result only changes when new wellness data arrives, which the cache key
 * fingerprint already captures. Redis is treated as strictly best-effort: a
 * cache outage must never break the endpoint.</p>
 */
@Component
public class CombinedInsightCache {

    private static final Logger log = LoggerFactory.getLogger(CombinedInsightCache.class);

    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final Duration ttl;

    public CombinedInsightCache(
            StringRedisTemplate redis,
            ObjectMapper objectMapper,
            @Value("${mindease.combined.cache-ttl:30m}") Duration ttl) {
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.ttl = ttl;
    }

    public Optional<CombinedInsightDto> get(String userId, String fingerprint) {
        try {
            String json = redis.opsForValue().get(key(userId, fingerprint));
            if (json == null || json.isBlank()) {
                return Optional.empty();
            }
            return Optional.of(objectMapper.readValue(json, CombinedInsightDto.class))
                    .map(CombinedInsightDto::withCached);
        } catch (Exception e) {
            log.debug("combined_insight_cache_miss reason={}", e.getMessage());
            return Optional.empty();
        }
    }

    public void put(String userId, String fingerprint, CombinedInsightDto dto) {
        try {
            redis.opsForValue().set(
                    key(userId, fingerprint),
                    objectMapper.writeValueAsString(dto),
                    ttl);
        } catch (Exception e) {
            log.debug("combined_insight_cache_write_failed reason={}", e.getMessage());
        }
    }

    private static String key(String userId, String fingerprint) {
        return "combined-insight:v1:" + userId + ":" + fingerprint;
    }
}
