package com.mindease.backend.wellness.dto;

import java.time.Instant;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Result of a real-time combined mental + physical wellness analysis.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record CombinedWellnessAnalysisDto(
        String analysisId,
        String type,
        Instant analyzedAt,
        boolean available,
        String overallStatus,
        String narrative,
        List<CombinedWellnessAnalysisDto.Suggestion> suggestions,
        List<String> correlations,
        List<String> cautions,
        String generatedBy,
        boolean safetyFlag,
        boolean cached,
        String note,
        CombinedWellnessAnalysisDto.InputSummary inputSummary,
        CombinedWellnessAnalysisDto.Provenance provenance,
        List<WellnessAdviceDto> advice,
        List<String> focusAreas,
        List<String> nextActions,
        WellnessComparisonDto comparison,
        List<GoalTargetSuggestion> goalTargetSuggestions) {

    public record Suggestion(String title, String description, String category) {
    }

    /** A validated, data-supported target the user may choose to adopt. */
    public record GoalTargetSuggestion(
            String metric,
            Integer value,
            String unit,
            String rationale) {
    }

    public record InputSummary(
            boolean mentalAvailable,
            boolean physicalAvailable,
            boolean hasSufficientData,
            Integer mentalWellnessScore,
            Integer physicalDataDays,
            Instant latestMentalAt,
            Instant latestPhysicalAt) {
    }

    public record Provenance(
            String source,
            String schemaVersion,
            List<String> inputReferences,
            Instant analyzedAt) {
    }

    public CombinedWellnessAnalysisDto withCached() {
        return new CombinedWellnessAnalysisDto(analysisId, type, analyzedAt, available,
                overallStatus, narrative, suggestions, correlations, cautions,
                generatedBy, safetyFlag, true, note, inputSummary, provenance,
                advice, focusAreas, nextActions, comparison, goalTargetSuggestions);
    }

    public static CombinedWellnessAnalysisDto unavailable(String note) {
        return new CombinedWellnessAnalysisDto(
                null, "COMBINED", Instant.now(), false, "INSUFFICIENT_DATA",
                null, List.of(), List.of(), List.of(), "rules", false, false, note,
                null, null, List.of(), List.of(), List.of(), null, List.of());
    }
}
