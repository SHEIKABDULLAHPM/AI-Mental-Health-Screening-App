package com.mindease.backend.features.physical.dto;

import java.time.LocalDate;
import java.util.List;

/**
 * Weekly trend payload. Every aggregate is nullable: null means the source
 * data never arrived, never "zero".
 */
public record WeeklySummaryResponse(
        LocalDate periodStart,
        LocalDate periodEnd,
        int daysWithData,
        Integer totalSteps,
        Double averageSteps,
        Double totalDistanceMeters,
        Double totalCaloriesKcal,
        Integer bestStepDay,
        LocalDate bestStepDate,
        int sleepSessions,
        Long averageSleepMillis,
        List<ActivityHistoryResponse.ActivityDay> days) {
}
