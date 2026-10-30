package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;

import org.junit.jupiter.api.Test;

import com.mindease.backend.features.physical.domain.HealthMetricType;

class HealthDataValidatorTest {

    private final HealthDataValidator validator = new HealthDataValidator();
    private final Instant now = Instant.parse("2026-10-06T12:00:00Z");

    // ──────────────────────────────────────── reading validation

    @Test
    void steps_areAccepted_inCountUnit() {
        var outcome = validator.validateReading(HealthMetricType.STEPS, 6842d, "steps",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isTrue();
        assertThat(outcome.value()).isEqualTo(6842d);
        assertThat(outcome.unit()).isEqualTo("count");
    }

    @Test
    void steps_negativeValue_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.STEPS, -1d, "steps",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains(">= 0");
    }

    @Test
    void steps_beyondPlausibleDailyMaximum_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.STEPS, 1_500_000d, "count",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("plausible");
    }

    @Test
    void distance_kilometers_normalizeToMeters() {
        var outcome = validator.validateReading(HealthMetricType.DISTANCE, 4.8, "km",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isTrue();
        assertThat(outcome.value()).isEqualTo(4800d);
        assertThat(outcome.unit()).isEqualTo("m");
    }

    @Test
    void distance_miles_normalizeToMeters() {
        var outcome = validator.validateReading(HealthMetricType.DISTANCE, 1.0, "mi",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isTrue();
        assertThat(outcome.value()).isCloseTo(1609.344d, org.assertj.core.data.Offset.offset(0.001d));
    }

    @Test
    void distance_unknownUnit_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.DISTANCE, 4.8, "furlongs",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("Unsupported distance unit");
    }

    @Test
    void calories_kilojoules_normalizeToKcal() {
        var outcome = validator.validateReading(HealthMetricType.CALORIES, 418.4, "kJ",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isTrue();
        assertThat(outcome.value()).isCloseTo(100d, org.assertj.core.data.Offset.offset(0.01d));
        assertThat(outcome.unit()).isEqualTo("kcal");
    }

    @Test
    void calories_negative_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.CALORIES, -5d, "kcal",
                now.minus(Duration.ofMinutes(5)), now);
        assertThat(outcome.valid()).isFalse();
    }

    @Test
    void heartRate_belowPhysiologicalRange_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.HEART_RATE, 5d, "bpm",
                now.minusSeconds(30), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("Heart rate");
    }

    @Test
    void heartRate_abovePhysiologicalRange_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.HEART_RATE, 300d, "bpm",
                now.minusSeconds(30), now);
        assertThat(outcome.valid()).isFalse();
    }

    @Test
    void heartRate_plausibleValue_isAccepted() {
        var outcome = validator.validateReading(HealthMetricType.HEART_RATE, 72d, "bpm",
                now.minusSeconds(30), now);
        assertThat(outcome.valid()).isTrue();
        assertThat(outcome.value()).isEqualTo(72d);
    }

    @Test
    void futureTimestamp_beyondClockSkew_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.STEPS, 10d, "steps",
                now.plus(Duration.ofHours(2)), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("future");
    }

    @Test
    void timestamp_olderThanWindow_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.STEPS, 10d, "steps",
                now.minus(Duration.ofDays(200)), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("older");
    }

    @Test
    void nanValue_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.STEPS, Double.NaN, "steps",
                now.minus(Duration.ofMinutes(1)), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("finite");
    }

    @Test
    void nullValue_isRejected() {
        var outcome = validator.validateReading(HealthMetricType.STEPS, null, "steps",
                now.minus(Duration.ofMinutes(1)), now);
        assertThat(outcome.valid()).isFalse();
    }

    // ──────────────────────────────────────── battery

    @Test
    void battery_withinRange_isValid() {
        assertThat(validator.validateBattery(0)).isNull();
        assertThat(validator.validateBattery(82)).isNull();
        assertThat(validator.validateBattery(100)).isNull();
        assertThat(validator.validateBattery(null)).isNull();
    }

    @Test
    void battery_outOfRange_isInvalid() {
        assertThat(validator.validateBattery(-1)).isNotNull();
        assertThat(validator.validateBattery(101)).isNotNull();
    }

    // ──────────────────────────────────────── sleep

    @Test
    void sleep_validWindow_isAccepted() {
        Instant start = now.minus(Duration.ofHours(8));
        var outcome = validator.validateSleep(start, now.minus(Duration.ofHours(1)), null, now);
        assertThat(outcome.valid()).isTrue();
        assertThat(outcome.value()).isEqualTo(Duration.ofHours(7).toMillis());
    }

    @Test
    void sleep_endBeforeStart_isRejected() {
        var outcome = validator.validateSleep(now, now.minus(Duration.ofHours(1)), null, now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("after start");
    }

    @Test
    void sleep_longerThanDay_isRejected() {
        var outcome = validator.validateSleep(now.minus(Duration.ofHours(30)),
                now.minus(Duration.ofHours(1)), null, now);
        assertThat(outcome.valid()).isFalse();
    }

    @Test
    void sleep_durationInconsistentWithWindow_isRejected() {
        Instant start = now.minus(Duration.ofHours(8));
        Instant end = now.minus(Duration.ofHours(1));
        var outcome = validator.validateSleep(start, end, Duration.ofHours(2).toMillis(), now);
        assertThat(outcome.valid()).isFalse();
        assertThat(outcome.error()).contains("does not match");
    }

    // ──────────────────────────────────────── exercise

    @Test
    void exercise_durationInMinutes_isNormalized() {
        var outcome = validator.validateReading(HealthMetricType.EXERCISE, 42d, "min",
                now.minus(Duration.ofMinutes(10)), now);
        assertThat(outcome.valid()).isTrue();
        assertThat(outcome.value()).isEqualTo(42d);
        assertThat(outcome.unit()).isEqualTo("min");
    }

    @Test
    void exercise_negativeWindow_isRejected() {
        var outcome = validator.validateExercise(now, now.minus(Duration.ofMinutes(5)), null, now);
        assertThat(outcome.valid()).isFalse();
    }

    // ──────────────────────────────────────── optional HR

    @Test
    void optionalHeartRate_null_isValid() {
        assertThat(validator.validateHeartRateOrNull(null)).isNull();
    }

    @Test
    void optionalHeartRate_implausible_isInvalid() {
        assertThat(validator.validateHeartRateOrNull(400d)).isNotNull();
    }
}
