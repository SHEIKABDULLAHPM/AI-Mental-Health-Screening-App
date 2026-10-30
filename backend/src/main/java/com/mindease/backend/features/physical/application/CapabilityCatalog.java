package com.mindease.backend.features.physical.application;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

import org.springframework.stereotype.Component;

/**
 * Canonical capability identifiers and their presentation metadata.
 *
 * <p>Metric identifiers deliberately include capabilities that are not health
 * readings (battery, firmware, GPS route, body composition) so that
 * "unsupported" can be represented explicitly instead of being implied by
 * absence.</p>
 */
@Component
public class CapabilityCatalog {

    public record Definition(String id, String label, String unit, boolean healthMetric) {
    }

    private static final Map<String, Definition> DEFINITIONS = new LinkedHashMap<>();

    static {
        register("STEPS", "Steps", "steps", true);
        register("DISTANCE", "Distance", "m", true);
        register("CALORIES", "Calories", "kcal", true);
        register("ACTIVE_MINUTES", "Active minutes", "min", true);
        register("HEART_RATE", "Heart rate", "bpm", true);
        register("RESTING_HEART_RATE", "Resting heart rate", "bpm", true);
        register("HEART_RATE_VARIABILITY", "Heart-rate variability", "ms", true);
        register("SPO2", "Blood oxygen (SpO2)", "%", true);
        register("SLEEP", "Sleep duration", "min", true);
        register("SLEEP_STAGES", "Sleep stages", "min", false);
        register("EXERCISE", "Workouts", "min", true);
        register("GPS_ROUTE", "GPS route", "route", false);
        register("BATTERY_LEVEL", "Battery level", "%", false);
        register("FIRMWARE_INFO", "Firmware version", "text", false);
        register("DEVICE_MODEL", "Device model", "text", false);
        register("BODY_WEIGHT", "Body weight", "kg", true);
        register("BODY_HEIGHT", "Body height", "cm", true);
        register("BODY_FAT", "Body-fat percentage", "%", true);
        register("MUSCLE_MASS", "Muscle mass", "kg", true);
        register("HYDRATION", "Hydration", "ml", true);
    }

    private static void register(String id, String label, String unit, boolean healthMetric) {
        DEFINITIONS.put(id, new Definition(id, label, unit, healthMetric));
    }

    public Optional<Definition> find(String id) {
        if (id == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(DEFINITIONS.get(id.trim().toUpperCase()));
    }

    public Definition require(String id) {
        return find(id).orElseThrow(() -> new IllegalArgumentException(
                "Unknown capability: " + id));
    }

    public Map<String, Definition> all() {
        return java.util.Collections.unmodifiableMap(DEFINITIONS);
    }
}
