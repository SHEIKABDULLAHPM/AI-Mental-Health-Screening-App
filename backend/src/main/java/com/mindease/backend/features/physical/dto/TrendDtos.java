package com.mindease.backend.features.physical.dto;

import java.time.LocalDate;
import java.util.List;

/**
 * Historical trend contract. Only days that actually hold a record appear in
 * {@code points}; gaps are reported through the coverage counters and are never
 * filled by interpolation.
 */
public final class TrendDtos {

    private TrendDtos() {
    }

    public record TrendPoint(
            LocalDate date,
            double value,
            String source) {
    }

    public record MetricTrend(
            String metric,
            String label,
            String unit,
            String aggregation,
            List<TrendPoint> points,
            Double average,
            Double previousAverage,
            Double changePercent,
            int daysWithData,
            int windowDays,
            String quality,
            String note) {
    }

    public record TrendsResponse(
            LocalDate from,
            LocalDate to,
            int windowDays,
            int previousWindowDays,
            List<MetricTrend> metrics,
            List<String> coverageNotes) {
    }
}
