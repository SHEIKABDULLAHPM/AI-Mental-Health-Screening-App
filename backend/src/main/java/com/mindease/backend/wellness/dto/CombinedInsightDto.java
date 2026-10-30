package com.mindease.backend.wellness.dto;

import java.time.Instant;
import java.util.List;

import com.mindease.backend.features.physical.dto.InsightDtos;

/**
 * Combined mental + physical insight shown on the dashboard.
 *
 * <p>{@code generatedBy} distinguishes AI-authored wording from the
 * deterministic composer. The client must never present rule-based text as
 * generative AI. {@code safetyFlag} is repeated here so the support surface
 * can render even if the combined call is the only thing the screen loaded.</p>
 */
public record CombinedInsightDto(
        Instant generatedAt,
        boolean available,
        String narrative,
        List<Suggestion> suggestions,
        String generatedBy,
        boolean safetyFlag,
        String note,
        boolean cached,
        InsightDtos.DataCoverage coverage) {

    public record Suggestion(String title, String description, String category) {
    }

    public CombinedInsightDto withCached() {
        return new CombinedInsightDto(generatedAt, available, narrative, suggestions,
                generatedBy, safetyFlag, note, true, coverage);
    }

    public static CombinedInsightDto unavailable() {
        return new CombinedInsightDto(Instant.now(), false, null, List.of(), null,
                false, "Complete your screening to unlock a combined mind-body insight.",
                false, null);
    }
}
