package com.mindease.backend.features.physical.domain;

/**
 * Provider-independent health metric identifiers. Device-specific packet
 * structures are normalized into these values before they ever reach this
 * domain.
 */
public enum HealthMetricType {

    STEPS("steps", "count"),
    DISTANCE("distance", "m"),
    CALORIES("calories", "kcal"),
    HEART_RATE("heart_rate", "bpm"),
    RESTING_HEART_RATE("resting_heart_rate", "bpm"),
    HEART_RATE_VARIABILITY("hrv", "ms"),
    SPO2("spo2", "%"),
    SLEEP("sleep", "min"),
    ACTIVE_MINUTES("active_minutes", "min"),
    EXERCISE("exercise", "min");

    private final String apiName;
    private final String canonicalUnit;

    HealthMetricType(String apiName, String canonicalUnit) {
        this.apiName = apiName;
        this.canonicalUnit = canonicalUnit;
    }

    /** Stable wire-format name used by the API (snake_case). */
    public String apiName() {
        return apiName;
    }

    /** Canonical internal unit: meters, kcal, bpm, minutes or count. */
    public String canonicalUnit() {
        return canonicalUnit;
    }

    public static HealthMetricType fromApiName(String value) {
        if (value == null) {
            return null;
        }
        for (HealthMetricType type : values()) {
            if (type.apiName.equalsIgnoreCase(value) || type.name().equalsIgnoreCase(value)) {
                return type;
            }
        }
        return null;
    }
}
