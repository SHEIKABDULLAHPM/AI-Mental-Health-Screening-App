package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.util.List;

/**
 * Heart-rate history. Resting heart rate is {@code null} unless the device
 * actually exposes it; {@code averageToday} is computed server-side from
 * today's readings and is null when there are none.
 */
public record HeartRateResponse(
        boolean supported,
        boolean available,
        Double latest,
        Double averageToday,
        Double resting,
        String unit,
        Instant updatedAt,
        List<Point> readings) {

    public record Point(Instant timestamp, Double value) {
    }

    public static HeartRateResponse unsupported() {
        return new HeartRateResponse(false, false, null, null, null, "bpm", null, List.of());
    }

    public static HeartRateResponse noData() {
        return new HeartRateResponse(true, false, null, null, null, "bpm", null, List.of());
    }
}
