package com.mindease.backend.features.physical.application;

import java.time.Duration;
import java.time.Instant;

import org.springframework.stereotype.Component;

import com.mindease.backend.features.physical.domain.HealthMetricType;

/**
 * Server-side data-quality gate for every incoming health measurement.
 *
 * <p>Pipeline stage represented here: payload validation → unit normalization
 * → range validation → timestamp validation. Anything that fails is rejected
 * with a user-safe reason; invalid data is never silently accepted.</p>
 */
@Component
public class HealthDataValidator {

    /** Tolerated clock skew when a device reports a future timestamp. */
    public static final Duration MAX_CLOCK_SKEW = Duration.ofMinutes(5);

    /** Oldest timestamp still accepted (long-offline reconciliation). */
    public static final Duration MAX_AGE = Duration.ofDays(90);

    public static final double MAX_STEPS_PER_DAY = 1_000_000d;
    public static final double MAX_DISTANCE_METERS_PER_DAY = 500_000d;
    public static final double MAX_CALORIES_PER_DAY = 30_000d;
    public static final int MIN_HEART_RATE_BPM = 20;
    public static final int MAX_HEART_RATE_BPM = 250;
    public static final Duration MAX_SLEEP = Duration.ofHours(24);
    public static final int MAX_BATTERY = 100;

    /** Outcome of validating one measurement. */
    public record Outcome(boolean valid, double value, String unit, String error) {
        static Outcome ok(double value, String unit) {
            return new Outcome(true, value, unit, null);
        }

        static Outcome reject(String error) {
            return new Outcome(false, 0, null, error);
        }
    }

    /**
     * Validates and normalizes a raw reading into the metric's canonical unit.
     *
     * @param metricType    normalized metric type (never null)
     * @param value         raw numeric value
     * @param unit          raw unit as sent by the client (nullable)
     * @param timestamp     measurement instant (never null)
     * @param now           server clock, injected for testability
     */
    public Outcome validateReading(HealthMetricType metricType, Double value,
                                   String unit, Instant timestamp, Instant now) {
        if (metricType == null) {
            return Outcome.reject("Unknown metric type");
        }
        if (value == null || value.isNaN() || value.isInfinite()) {
            return Outcome.reject("Value must be a finite number");
        }
        if (timestamp == null) {
            return Outcome.reject("Timestamp is required");
        }
        if (timestamp.isAfter(now.plus(MAX_CLOCK_SKEW))) {
            return Outcome.reject("Timestamp is in the future");
        }
        if (timestamp.isBefore(now.minus(MAX_AGE))) {
            return Outcome.reject("Timestamp is older than the supported window");
        }
        return normalizeAndRange(metricType, value, unit);
    }

    /**
     * Unit normalization + range validation only (no timestamp rules). Used by
     * day-level aggregates where the calendar day already passed its own
     * window check.
     */
    public Outcome normalizeAndRange(HealthMetricType metricType, Double value, String unit) {
        if (metricType == null) {
            return Outcome.reject("Unknown metric type");
        }
        if (value == null || value.isNaN() || value.isInfinite()) {
            return Outcome.reject("Value must be a finite number");
        }
        double normalized;
        String canonicalUnit = metricType.canonicalUnit();
        try {
            normalized = normalize(metricType, value, unit, canonicalUnit);
        } catch (IllegalArgumentException e) {
            return Outcome.reject(e.getMessage());
        }
        String rangeError = checkRange(metricType, normalized);
        if (rangeError != null) {
            return Outcome.reject(rangeError);
        }
        return Outcome.ok(normalized, canonicalUnit);
    }

    /** Battery is device status, not a health metric: 0–100 only. */
    public String validateBattery(Integer batteryLevel) {
        if (batteryLevel == null) {
            return null;
        }
        if (batteryLevel < 0 || batteryLevel > MAX_BATTERY) {
            return "batteryLevel must be between 0 and 100";
        }
        return null;
    }

    /** Sleep window validation; duration is derived when not supplied. */
    public Outcome validateSleep(Instant start, Instant end, Long durationMillis, Instant now) {
        if (start == null || end == null) {
            return Outcome.reject("Sleep start and end times are required");
        }
        if (!end.isAfter(start)) {
            return Outcome.reject("Sleep end must be after start");
        }
        if (end.isAfter(now.plus(MAX_CLOCK_SKEW))) {
            return Outcome.reject("Sleep end is in the future");
        }
        if (start.isBefore(now.minus(MAX_AGE).minus(Duration.ofDays(7)))) {
            return Outcome.reject("Sleep session is older than the supported window");
        }
        long millis = Duration.between(start, end).toMillis();
        if (durationMillis != null && durationMillis > 0) {
            long skew = Math.abs(durationMillis - millis);
            // Tolerate small device-side rounding, reject inconsistent payloads.
            if (skew > Duration.ofHours(2).toMillis()) {
                return Outcome.reject("Sleep duration does not match start/end times");
            }
            millis = durationMillis;
        }
        if (millis <= 0 || millis > MAX_SLEEP.toMillis()) {
            return Outcome.reject("Sleep duration must be between 0 and 24 hours");
        }
        return Outcome.ok(millis, "ms");
    }

    /** Exercise window validation; duration is derived when not supplied. */
    public Outcome validateExercise(Instant start, Instant end, Long durationMillis, Instant now) {
        if (start == null || end == null) {
            return Outcome.reject("Exercise start and end times are required");
        }
        if (!end.isAfter(start)) {
            return Outcome.reject("Exercise end must be after start");
        }
        if (end.isAfter(now.plus(MAX_CLOCK_SKEW))) {
            return Outcome.reject("Exercise end is in the future");
        }
        long millis = Duration.between(start, end).toMillis();
        if (durationMillis != null && durationMillis > 0) {
            long skew = Math.abs(durationMillis - millis);
            if (skew > Duration.ofHours(1).toMillis()) {
                return Outcome.reject("Exercise duration does not match start/end times");
            }
            millis = durationMillis;
        }
        if (millis <= 0 || millis > MAX_SLEEP.toMillis()) {
            return Outcome.reject("Exercise duration must be between 0 and 24 hours");
        }
        return Outcome.ok(millis, "ms");
    }

    /** Heart-rate range check used for exercise HR aggregates too. */
    public String validateHeartRate(Double bpm) {
        if (bpm == null || bpm.isNaN() || bpm.isInfinite()) {
            return "Heart rate must be a finite number";
        }
        if (bpm < MIN_HEART_RATE_BPM || bpm > MAX_HEART_RATE_BPM) {
            return "Heart rate must be between " + MIN_HEART_RATE_BPM + " and "
                    + MAX_HEART_RATE_BPM + " bpm";
        }
        return null;
    }

    /**
     * Optional heart-rate check: {@code null} (not provided by the device) is
     * valid; a provided value must be plausible.
     */
    public String validateHeartRateOrNull(Double bpm) {
        if (bpm == null) {
            return null;
        }
        return validateHeartRate(bpm);
    }

    private double normalize(HealthMetricType metricType, double value, String unit,
                             String canonicalUnit) {
        String raw = unit == null || unit.isBlank() ? canonicalUnit : unit.trim().toLowerCase();
        return switch (metricType) {
            case STEPS -> {
                if (!isAny(raw, "count", "steps", "step")) {
                    throw new IllegalArgumentException("Steps unit must be 'steps'");
                }
                if (value < 0) {
                    throw new IllegalArgumentException("Steps must be >= 0");
                }
                yield value;
            }
            case DISTANCE -> switch (raw) {
                case "m", "meter", "meters" -> nonNegative(value, "Distance");
                case "km", "kilometer", "kilometers" -> nonNegative(value * 1000d, "Distance");
                case "cm", "centimeter", "centimeters" -> nonNegative(value / 100d, "Distance");
                case "mi", "mile", "miles" -> nonNegative(value * 1609.344d, "Distance");
                default -> throw new IllegalArgumentException("Unsupported distance unit: " + unit);
            };
            case CALORIES -> {
                if (!isAny(raw, "kcal", "cal", "kilojoule", "kj")) {
                    throw new IllegalArgumentException("Unsupported calorie unit: " + unit);
                }
                if (isAny(raw, "kj", "kilojoule")) {
                    // The unit conversion ran before the range check on the
                    // kJ path, which let a negative value through; validate
                    // the raw value in every branch.
                    yield nonNegative(value / 4.184d, "Calories");
                }
                yield nonNegative(value, "Calories");
            }
            case HEART_RATE -> {
                if (!isAny(raw, "bpm", "beat/min")) {
                    throw new IllegalArgumentException("Heart rate unit must be 'bpm'");
                }
                yield value;
            }
            case RESTING_HEART_RATE -> {
                if (!isAny(raw, "bpm", "beat/min")) {
                    throw new IllegalArgumentException("Resting heart rate unit must be 'bpm'");
                }
                yield value;
            }
            case HEART_RATE_VARIABILITY -> {
                // RMSSD/SDNN are millisecond measures. Anything else is a
                // different metric and must not be relabelled as HRV.
                if (!isAny(raw, "ms", "millisecond", "milliseconds")) {
                    throw new IllegalArgumentException("HRV unit must be 'ms'");
                }
                if (value <= 0) {
                    throw new IllegalArgumentException("HRV must be > 0 ms");
                }
                yield value;
            }
            case SPO2 -> {
                if (!isAny(raw, "%", "percent")) {
                    throw new IllegalArgumentException("SpO2 unit must be '%'");
                }
                yield value;
            }
            case SLEEP, EXERCISE, ACTIVE_MINUTES -> {
                if (!isAny(raw, "min", "minutes", "minute", "ms")) {
                    throw new IllegalArgumentException("Duration unit must be 'min' or 'ms'");
                }
                yield isAny(raw, "ms") ? value / 60_000d : value;
            }
        };
    }

    private String checkRange(HealthMetricType metricType, double value) {
        return switch (metricType) {
            case STEPS -> value > MAX_STEPS_PER_DAY ? "Steps exceed the plausible daily maximum" : null;
            case DISTANCE -> value > MAX_DISTANCE_METERS_PER_DAY
                    ? "Distance exceeds the plausible daily maximum" : null;
            case CALORIES -> value > MAX_CALORIES_PER_DAY
                    ? "Calories exceed the plausible daily maximum" : null;
            case HEART_RATE -> (value < MIN_HEART_RATE_BPM || value > MAX_HEART_RATE_BPM)
                    ? "Heart rate must be between " + MIN_HEART_RATE_BPM + " and "
                            + MAX_HEART_RATE_BPM + " bpm"
                    : null;
            case RESTING_HEART_RATE -> (value < 25 || value > 150)
                    ? "Resting heart rate must be between 25 and 150 bpm" : null;
            case HEART_RATE_VARIABILITY -> (value < 1 || value > 500)
                    ? "HRV must be between 1 and 500 ms" : null;
            case SPO2 -> (value < 50 || value > 100)
                    ? "SpO2 must be between 50 and 100 %" : null;
            case SLEEP, EXERCISE, ACTIVE_MINUTES -> (value < 0 || value > 1440)
                    ? "Duration must be between 0 and 1440 minutes" : null;
        };
    }

    private static boolean isAny(String value, String... options) {
        for (String option : options) {
            if (option.equalsIgnoreCase(value)) {
                return true;
            }
        }
        return false;
    }

    /** Cumulative metrics may be zero but never negative. */
    private static double nonNegative(double value, String label) {
        if (value < 0) {
            throw new IllegalArgumentException(label + " must be >= 0");
        }
        return value;
    }
}
