package com.mindease.backend.config;

import java.time.Duration;
import java.util.List;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Synora application configuration bound from environment variables
 * (see resources/application.yml). Secrets are never committed; each value
 * has a safe development default.
 */
@ConfigurationProperties(prefix = "mindease")
public class AppProperties {

    private final Jwt jwt = new Jwt();
    private final Cors cors = new Cors();
    private final RateLimit rateLimit = new RateLimit();
    private final Otp otp = new Otp();
    private final Audit audit = new Audit();
    private final Ai ai = new Ai();

    public Jwt getJwt() {
        return jwt;
    }

    public Cors getCors() {
        return cors;
    }

    public RateLimit getRateLimit() {
        return rateLimit;
    }

    public Otp getOtp() {
        return otp;
    }

    public Audit getAudit() {
        return audit;
    }

    public Ai getAi() {
        return ai;
    }

    /** Self-issued JWT configuration. */
    public static class Jwt {
        private String secret;
        private String issuer = "mindease";
        private Duration accessExpiration = Duration.ofMinutes(15);
        private Duration refreshExpiration = Duration.ofDays(7);

        public String getSecret() {
            return secret;
        }

        public void setSecret(String secret) {
            this.secret = secret;
        }

        public String getIssuer() {
            return issuer;
        }

        public void setIssuer(String issuer) {
            this.issuer = issuer;
        }

        public Duration getAccessExpiration() {
            return accessExpiration;
        }

        public void setAccessExpiration(Duration accessExpiration) {
            this.accessExpiration = accessExpiration;
        }

        public Duration getRefreshExpiration() {
            return refreshExpiration;
        }

        public void setRefreshExpiration(Duration refreshExpiration) {
            this.refreshExpiration = refreshExpiration;
        }
    }

    /** Cross-origin configuration for the Flutter (web/desktop) and Android clients. */
    public static class Cors {
        private List<String> allowedOrigins = List.of("*");

        public List<String> getAllowedOrigins() {
            return allowedOrigins;
        }

        public void setAllowedOrigins(List<String> allowedOrigins) {
            this.allowedOrigins = allowedOrigins;
        }
    }

    /** Simple per-IP fixed-window rate limiter (Redis backed when available). */
    public static class RateLimit {
        private int defaultLimit = 60;
        private Duration window = Duration.ofMinutes(1);
        private int authLimit = 10;

        public int getDefaultLimit() {
            return defaultLimit;
        }

        public void setDefaultLimit(int defaultLimit) {
            this.defaultLimit = defaultLimit;
        }

        public Duration getWindow() {
            return window;
        }

        public void setWindow(Duration window) {
            this.window = window;
        }

        public int getAuthLimit() {
            return authLimit;
        }

        public void setAuthLimit(int authLimit) {
            this.authLimit = authLimit;
        }
    }

    /** Password-reset OTP policy. */
    public static class Otp {
        private int length = 6;
        private Duration expiration = Duration.ofMinutes(10);
        private int maxAttempts = 5;

        public int getLength() {
            return length;
        }

        public void setLength(int length) {
            this.length = length;
        }

        public Duration getExpiration() {
            return expiration;
        }

        public void setExpiration(Duration expiration) {
            this.expiration = expiration;
        }

        public int getMaxAttempts() {
            return maxAttempts;
        }

        public void setMaxAttempts(int maxAttempts) {
            this.maxAttempts = maxAttempts;
        }
    }

    /** Security audit logging switch. */
    public static class Audit {
        private boolean enabled = true;

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }
    }

    /** AI analysis job queue configuration. */
    public static class Ai {
        private String tasksQueue = "ai_tasks";
        private int maxAttempts = 3;
        /**
         * Shared key protecting the internal callback endpoints. There is NO
         * safe default: it must be supplied via {@code AI_INTERNAL_API_KEY}
         * (enforced in non-dev profiles at startup, see
         * {@code InternalKeyStartupValidator}).
         */
        private String internalApiKey = "";
        /**
         * TTL after which a {@code PROCESSING} job is considered wedged and
         * swept to {@code FAILED} so the owner can retry it.
         */
        private Duration claimTimeout = Duration.ofMinutes(5);
        /** How often the stale-job sweeper runs, in milliseconds. */
        private long staleSweepInterval = 60_000L;

        public String getTasksQueue() {
            return tasksQueue;
        }

        public void setTasksQueue(String tasksQueue) {
            this.tasksQueue = tasksQueue;
        }

        public int getMaxAttempts() {
            return maxAttempts;
        }

        public void setMaxAttempts(int maxAttempts) {
            this.maxAttempts = maxAttempts;
        }

        public String getInternalApiKey() {
            return internalApiKey;
        }

        public void setInternalApiKey(String internalApiKey) {
            this.internalApiKey = internalApiKey;
        }

        public Duration getClaimTimeout() {
            return claimTimeout;
        }

        public void setClaimTimeout(Duration claimTimeout) {
            this.claimTimeout = claimTimeout;
        }

        public long getStaleSweepInterval() {
            return staleSweepInterval;
        }

        public void setStaleSweepInterval(long staleSweepInterval) {
            this.staleSweepInterval = staleSweepInterval;
        }
    }
}