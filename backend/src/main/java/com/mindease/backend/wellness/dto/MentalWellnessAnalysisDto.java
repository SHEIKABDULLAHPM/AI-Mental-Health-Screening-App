package com.mindease.backend.wellness.dto;

import java.time.Instant;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Result of a real-time mental wellness analysis.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record MentalWellnessAnalysisDto(
        String analysisId,
        String type,
        Instant analyzedAt,
        boolean available,
        Integer wellnessScore,
        String stressLevel,
        Integer lifestyleScore,
        String sleepQuality,
        String primaryFocus,
        String insight,
        List<String> recommendations,
        String generatedBy,
        boolean safetyFlag,
        boolean cached,
        String note,
        MentalWellnessAnalysisDto.InputSummary inputSummary,
        MentalWellnessAnalysisDto.Provenance provenance,
        List<WellnessAdviceDto> advice,
        List<String> focusAreas,
        List<String> nextActions,
        WellnessComparisonDto comparison,
        List<GoalTargetSuggestion> goalTargetSuggestions) {

    /** A validated, data-supported target the user may choose to adopt. */
    public record GoalTargetSuggestion(
            String metric,
            Integer value,
            String unit,
            String rationale) {
    }

    public record InputSummary(
            boolean hasWellnessProfile,
            boolean hasRecentAssessment,
            boolean hasMoodData,
            Integer assessmentCount,
            Instant latestAssessmentAt,
            Instant latestMoodAt) {
    }

    public record Provenance(
            String source,
            String schemaVersion,
            List<String> inputReferences,
            Instant analyzedAt) {
    }

    public MentalWellnessAnalysisDto withCached() {
        return new MentalWellnessAnalysisDto(analysisId, type, analyzedAt, available,
                wellnessScore, stressLevel, lifestyleScore, sleepQuality, primaryFocus,
                insight, recommendations, generatedBy, safetyFlag, true, note,
                inputSummary, provenance, advice, focusAreas, nextActions, comparison,
                goalTargetSuggestions);
    }

    public static MentalWellnessAnalysisDto unavailable(String note) {
        return new MentalWellnessAnalysisDto(
                null, "MENTAL", Instant.now(), false, null, null, null, null, null,
                null, List.of(), "rules", false, false, note, null, null,
                List.of(), List.of(), List.of(), null, List.of());
    }
}
