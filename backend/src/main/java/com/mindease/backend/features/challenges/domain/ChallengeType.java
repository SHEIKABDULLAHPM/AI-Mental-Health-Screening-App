package com.mindease.backend.features.challenges.domain;

/**
 * Controlled challenge types. Each type maps to a real, verifiable application
 * activity source. A type is only enabled here when its activity source can be
 * reliably validated server-side (i.e. an actual persisted record exists).
 *
 * <p>Never treats an arbitrary string from the client as a challenge type.
 */
public enum ChallengeType {

    /** Progress derived from persisted MoodEntry records. */
    MOOD_CHECK_IN("mood"),

    /** Progress derived from persisted JournalEntry records. */
    JOURNALING("journal"),

    /** Progress derived from completed relaxation / breathing activities. */
    RELAXATION("relax"),

    /** Progress derived from a completed recommendation activity. */
    HEALTHY_ROUTINE("recommendation"),

    /** Progress derived from completing a supported game challenge. */
    GAME_ACTIVITY("game");

    private final String activitySource;

    ChallengeType(String activitySource) {
        this.activitySource = activitySource;
    }

    public String activitySource() {
        return activitySource;
    }

    /**
     * Resolve a challenge type from its stored string value, returning null for
     * unknown values. This keeps the catalog controlled: unknown/legacy values
     * are never silently accepted as a real activity-backed type.
     */
    public static ChallengeType fromValue(String value) {
        if (value == null) {
            return null;
        }
        for (ChallengeType t : values()) {
            if (t.name().equalsIgnoreCase(value.trim())) {
                return t;
            }
        }
        return null;
    }
}
