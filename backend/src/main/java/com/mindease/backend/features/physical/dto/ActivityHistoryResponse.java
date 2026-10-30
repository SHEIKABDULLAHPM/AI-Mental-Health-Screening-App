package com.mindease.backend.features.physical.dto;

import java.time.LocalDate;
import java.util.List;

/**
 * Daily activity history / weekly trend. {@code available=false} means no
 * activity data has ever been received — clients must not render zeros.
 */
public record ActivityHistoryResponse(
        boolean available,
        List<ActivityDay> days) {

    public record ActivityDay(
            LocalDate date,
            Integer steps,
            Double distanceMeters,
            Double caloriesKcal,
            Integer activeMinutes) {
    }

    public static ActivityHistoryResponse empty() {
        return new ActivityHistoryResponse(false, List.of());
    }
}
