package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.util.List;

/**
 * Mind–Body insight contract.
 *
 * <p>Every insight is descriptive, carries the exact evidence it was derived
 * from, and states how much data it rests on. {@code confidence} is a data
 * coverage signal, not a medical probability; {@code disclaimer} is mandatory
 * so no client can render a pattern as a diagnosis.</p>
 */
public final class InsightDtos {

    private InsightDtos() {
    }

    public record Evidence(
            String source,
            String metric,
            Double current,
            Double baseline,
            String unit,
            int windowDays,
            int coverageDays,
            String comparison) {
    }

    public record DataCoverage(
            int windowDays,
            int daysWithActivity,
            int daysWithSleep,
            int daysWithHydration,
            int moodCheckins,
            int heartRateDays,
            List<String> missingSources) {
    }

    public record PatternInsight(
            String id,
            String title,
            String summary,
            String severity,
            String confidence,
            List<Evidence> evidence,
            DataCoverage coverage,
            String disclaimer) {
    }

    public record Recommendation(
            String id,
            String title,
            String description,
            String category,
            String source) {
    }

    public record InsightsResponse(
            Instant generatedAt,
            int windowDays,
            boolean sufficientData,
            List<PatternInsight> insights,
            List<Recommendation> recommendations,
            boolean aiEnhanced,
            DataCoverage coverage,
            List<String> limitations,
            String disclaimer) {
    }
}
