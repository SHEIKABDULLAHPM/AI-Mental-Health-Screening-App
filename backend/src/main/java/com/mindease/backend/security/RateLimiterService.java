package com.mindease.backend.security;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.stereotype.Service;

/**
 * Simple thread-safe fixed-window rate limiter keyed by an arbitrary string
 * (IP address, email, ...). Windows are reclaimed lazily on access. Suitable
 * for auth/OTP endpoints where in-process limiting is acceptable.
 */
@Service
public class RateLimiterService {

    private static final int MAX_KEYS = 10_000;

    private static final class Window {
        long start;
        int count;
    }

    private final ConcurrentHashMap<String, Window> windows = new ConcurrentHashMap<>();

    /**
     * @param key    discriminator (IP address, email, ...)
     * @param limit  maximum hits per window
     * @param window duration of the fixed window
     * @return true when the request is allowed, false when rate-limited
     */
    public synchronized boolean allow(String key, int limit, Duration window) {
        long now = System.currentTimeMillis();
        long windowMillis = window.toMillis();

        Window entry = windows.computeIfAbsent(key, k -> new Window());
        if (now - entry.start >= windowMillis) {
            entry.start = now;
            entry.count = 0;
        }
        if (++entry.count > limit) {
            if (windows.size() > MAX_KEYS) {
                windows.clear();
            }
            return false;
        }
        return true;
    }
}