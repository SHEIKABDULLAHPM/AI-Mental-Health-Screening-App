package com.mindease.backend.features.mood.application;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.mindease.backend.features.mood.domain.MoodEntry;

/**
 * Classifies mood trend direction from recent mood history.
 * Compares the user with their own history — never with population norms.
 * Does not diagnose any mental health condition.
 */
@Component
public class MoodTrendAnalyzer {

    /** Minimum entries required for a meaningful trend classification. */
    private static final int MIN_ENTRIES = 3;

    /**
     * Analyse recent mood entries and classify the trend direction.
     *
     * @param entries recent entries ordered newest-first
     * @return trend classification with explanation
     */
    public Map<String, Object> analyzeTrend(List<MoodEntry> entries) {
        Map<String, Object> result = new LinkedHashMap<>();

        if (entries == null || entries.size() < MIN_ENTRIES) {
            result.put("direction", "unknown");
            result.put("description", "Not enough mood records to determine a trend.");
            result.put("dataPoints", entries != null ? entries.size() : 0);
            return result;
        }

        // Build daily average values (oldest first for time-series)
        List<Double> dailyValues = computeDailyAverages(entries);

        if (dailyValues.size() < 2) {
            result.put("direction", "stable");
            result.put("description", "Your mood has been consistent recently.");
            result.put("dataPoints", dailyValues.size());
            return result;
        }

        // Split into first half and second half for comparison
        int mid = dailyValues.size() / 2;
        double firstHalfAvg = dailyValues.subList(0, mid).stream()
                .mapToDouble(Double::doubleValue).average().orElse(0.0);
        double secondHalfAvg = dailyValues.subList(mid, dailyValues.size()).stream()
                .mapToDouble(Double::doubleValue).average().orElse(0.0);

        // Calculate volatility (standard deviation)
        double avgAll = dailyValues.stream()
                .mapToDouble(Double::doubleValue).average().orElse(0.0);
        double variance = dailyValues.stream()
                .mapToDouble(v -> Math.pow(v - avgAll, 2))
                .average().orElse(0.0);
        double stdDev = Math.sqrt(variance);

        double difference = secondHalfAvg - firstHalfAvg;
        double threshold = Math.max(0.3, stdDev * 0.5);

        String direction;
        String description;

        if (Math.abs(difference) < threshold) {
            direction = "stable";
            description = "Your mood has been fairly consistent recently.";
        } else if (difference > 0) {
            if (difference > threshold * 2) {
                direction = "improving";
                description = "Your recent moods show a positive upward trend.";
            } else {
                direction = "improving";
                description = "Your mood appears to be trending slightly upward.";
            }
        } else {
            if (Math.abs(difference) > threshold * 2) {
                direction = "declining";
                description = "Your recent moods show a downward trend. "
                        + "Consider reaching out if this persists.";
            } else {
                direction = "declining";
                description = "Your mood appears to be trending slightly downward.";
            }
        }

        // Check for fluctuation: high variance relative to trend
        if (stdDev > 1.5 && Math.abs(difference) < threshold) {
            direction = "fluctuating";
            description = "Your mood has been varying quite a bit recently. "
                    + "This is normal — moods naturally fluctuate.";
        }

        result.put("direction", direction);
        result.put("description", description);
        result.put("dataPoints", dailyValues.size());
        result.put("averageValue", Math.round(avgAll * 10.0) / 10.0);
        result.put("volatility", Math.round(stdDev * 100.0) / 100.0);

        return result;
    }

    private List<Double> computeDailyAverages(List<MoodEntry> entries) {
        ZoneId utc = ZoneId.of("UTC");
        DateTimeFormatter dayFmt = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(utc);

        // Group entries by day (entries are newest-first, reverse for chronological)
        Map<String, List<Integer>> byDay = new LinkedHashMap<>();
        List<MoodEntry> reversed = new ArrayList<>(entries);
        java.util.Collections.reverse(reversed);

        for (MoodEntry entry : reversed) {
            if (entry.getRecordedAt() != null) {
                String dayKey = dayFmt.format(entry.getRecordedAt());
                byDay.computeIfAbsent(dayKey, k -> new ArrayList<>())
                        .add(moodToValue(entry.getMood()));
            }
        }

        return byDay.values().stream()
                .map(values -> values.stream().mapToInt(Integer::intValue).average().orElse(0.0))
                .toList();
    }

    /**
     * Single source of truth for mapping a mood id to its 1-6 trend value.
     * Shared by mood statistics, trend analysis, progress aggregation and
     * onboarding mood scoring — do not duplicate this table elsewhere.
     */
    public static int moodToValue(String mood) {
        return switch (mood) {
            case "very_happy" -> 6;
            case "happy" -> 5;
            case "calm" -> 4;
            case "okay" -> 3;
            case "low" -> 2;
            case "stressed" -> 1;
            default -> 3;
        };
    }
}
