package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * Exercise history. Optional measurements stay null when the device did not
 * provide them.
 */
public record ExerciseHistoryResponse(
        boolean available,
        Session latest,
        List<Session> sessions) {

    public record Session(
            LocalDate date,
            String type,
            Instant startTime,
            Instant endTime,
            Long durationMillis,
            Double distanceMeters,
            Double caloriesKcal,
            Double averageHeartRate,
            Double maximumHeartRate) {
    }

    public static ExerciseHistoryResponse empty() {
        return new ExerciseHistoryResponse(false, null, List.of());
    }
}
