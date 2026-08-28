package com.mindease.backend.features.mood.dto;

import java.util.Map;

/**
 * Aggregated mood statistics for the current user.
 * Returned by GET /api/v1/moods/stats.
 */
public record MoodStatisticsResponse(
        int totalEntries,
        int entriesThisWeek,
        int currentStreak,
        int longestStreak,
        String mostCommonMood,
        Double averageIntensity,
        Map<String, Long> moodDistribution) {
}
