package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

import com.mindease.backend.wellness.dto.WellnessAdviceDto;
import com.mindease.backend.wellness.dto.WellnessComparisonDto;

/**
 * Result of a real-time physical wellness analysis.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PhysicalWellnessAnalysisDto(
        String analysisId,
        String type,
        Instant analyzedAt,
        boolean available,
        String status,
        PhysicalWellnessAnalysisDto.Metrics metrics,
        List<String> patterns,
        List<String> recommendations,
        String generatedBy,
        boolean cached,
        String note,
        PhysicalWellnessAnalysisDto.InputSummary inputSummary,
        PhysicalWellnessAnalysisDto.Provenance provenance,
        List<WellnessAdviceDto> advice,
        List<String> focusAreas,
        List<String> nextActions,
        WellnessComparisonDto comparison,
        String narrative,
        List<GoalTargetSuggestion> goalTargetSuggestions) {

    /** A validated, data-supported target the user may choose to adopt. */
    public record GoalTargetSuggestion(
            String metric,
            Integer value,
            String unit,
            String rationale) {
    }

    public record Metrics(
            Integer stepsAverage,
            Double distanceKmAverage,
            Integer caloriesAverage,
            Integer activeMinutesAverage,
            Integer sleepHoursAverage,
            Integer sleepMinutesAverage,
            Double heartRateAverage,
            Double spo2Average,
            Double hrvAverage,
            Integer hydrationMlAverage) {
    }

    public record InputSummary(
            boolean hasWearableData,
            boolean hasRecentSync,
            boolean hasActivityData,
            boolean hasSleepData,
            boolean hasHeartRateData,
            Integer daysOfActivity,
            Integer daysOfSleep,
            Instant latestReadingAt,
            Instant latestSyncAt) {
    }

    public record Provenance(
            String source,
            String schemaVersion,
            List<String> inputReferences,
            Instant analyzedAt) {
    }

    public PhysicalWellnessAnalysisDto withCached() {
        return new PhysicalWellnessAnalysisDto(analysisId, type, analyzedAt, available,
                status, metrics, patterns, recommendations, generatedBy, true, note,
                inputSummary, provenance, advice, focusAreas, nextActions, comparison,
                narrative, goalTargetSuggestions);
    }

    public static PhysicalWellnessAnalysisDto unavailable(String note) {
        return new PhysicalWellnessAnalysisDto(
                null, "PHYSICAL", Instant.now(), false, "INSUFFICIENT_DATA",
                null, List.of(), List.of(), "rules", false, note, null, null,
                List.of(), List.of(), List.of(), null, null, List.of());
    }
}
