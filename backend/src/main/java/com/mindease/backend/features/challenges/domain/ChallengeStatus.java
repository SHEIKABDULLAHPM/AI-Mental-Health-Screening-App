package com.mindease.backend.features.challenges.domain;

/**
 * Lifecycle state machine for a UserChallenge.
 *
 * <p>Valid transitions (enforced server-side):</p>
 * <pre>
 *   AVAILABLE   → ACTIVE        (user starts)
 *   ACTIVE      → IN_PROGRESS   (at least one verified activity)
 *   IN_PROGRESS → COMPLETED     (target reached)
 *   ACTIVE      → EXPIRED       (period elapsed)
 *   IN_PROGRESS → EXPIRED       (period elapsed)
 * </pre>
 *
 * <p>Terminal and non-terminal invariants:</p>
 * <pre>
 *   COMPLETED → never leaves
 *   EXPIRED   → never leaves
 * </pre>
 *
 * <p>Flutter can never directly change this state; it is only derived from
 * server-verified activity.</p>
 */
public enum ChallengeStatus {

    AVAILABLE,
    ACTIVE,
    IN_PROGRESS,
    COMPLETED,
    EXPIRED;

    /**
     * Whether this status represents a user the user has started engaging with.
     */
    public boolean isStarted() {
        return this == ACTIVE || this == IN_PROGRESS;
    }

    /**
     * Whether this status may still receive activity-driven progress.
     */
    public boolean isOpenForProgress() {
        return this == ACTIVE || this == IN_PROGRESS;
    }

    public static ChallengeStatus fromValue(String value) {
        if (value == null) {
            return null;
        }
        for (ChallengeStatus s : values()) {
            if (s.name().equalsIgnoreCase(value.trim())) {
                return s;
            }
        }
        return null;
    }
}
