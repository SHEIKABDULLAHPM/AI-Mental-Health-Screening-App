package com.mindease.backend.features.challenges.domain;

/**
 * How often a challenge instance is evaluated and renewed.
 *
 * <p>DAILY challenges target a single verified activity per day; the period is
 * the user's local calendar day. WEEKLY challenges target N activities within a
 * week; the period is the user's local calendar week (ISO, Monday start).</p>
 */
public enum ChallengeFrequency {

    DAILY,
    WEEKLY;

    public static ChallengeFrequency fromValue(String value) {
        if (value == null) {
            return null;
        }
        for (ChallengeFrequency f : values()) {
            if (f.name().equalsIgnoreCase(value.trim())) {
                return f;
            }
        }
        return null;
    }
}
