package com.mindease.backend.security;

/**
 * Thread-local holder for the user's timezone, extracted from the
 * {@code X-User-Timezone} request header. Defaults to {@code null} (UTC fallback
 * in {@code ChallengePeriodCalculator}) when absent.
 *
 * <p>Set by {@code UserTimeZoneFilter}, cleared after the request completes.</p>
 */
public final class UserTimeZoneHolder {

    private static final ThreadLocal<String> HOLDER = new ThreadLocal<>();

    private UserTimeZoneHolder() {
    }

    public static void set(String zone) {
        HOLDER.set(zone);
    }

    public static String get() {
        return HOLDER.get();
    }

    public static void clear() {
        HOLDER.remove();
    }
}
