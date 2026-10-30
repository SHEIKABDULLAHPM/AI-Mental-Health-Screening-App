package com.mindease.backend.wellness.dto;

import java.time.Instant;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * How the current analysis compares with the previous stored one.
 *
 * <p>Produced deterministically from the two stored metric sets, never by the
 * AI service, so "what improved" is always traceable to numbers the user can
 * see. {@code hasPrevious} is false for a first analysis; that is reported
 * plainly instead of inventing a baseline.</p>
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record WellnessComparisonDto(
        boolean hasPrevious,
        Instant previousAnalyzedAt,
        Long daysSincePrevious,
        String overall,
        String summary,
        List<Change> changes,
        List<String> improved,
        List<String> declined,
        List<String> unchanged,
        List<String> habitInsights,
        List<String> nextActions) {

    /** One aspect compared between the two analyses. */
    public record Change(
            String aspect,
            String previous,
            String current,
            String direction,
            String explanation) {
    }

    public static WellnessComparisonDto firstAnalysis() {
        return new WellnessComparisonDto(false, null, null, "FIRST_ANALYSIS",
                "This is the first stored analysis, so there is no earlier result to "
                        + "compare against yet. Run it again after a few days of data.",
                List.of(), List.of(), List.of(), List.of(), List.of(), List.of());
    }
}
