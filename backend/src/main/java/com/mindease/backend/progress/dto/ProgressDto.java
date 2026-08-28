package com.mindease.backend.progress.dto;

import java.time.Instant;
import java.util.List;
import java.util.Map;

/**
 * Aggregated progress data computed from real user activity across all features.
 * Every field is derived from actual MongoDB data — no static or fabricated values.
 */
public record ProgressDto(
        // ── Wellness overview ──
        Integer wellnessScore,
        String wellnessScoreLabel,
        String wellnessTrend,

        // ── Mood progress ──
        MoodProgress mood,

        // ── Journal progress ──
        JournalProgress journal,

        // ── Activity progress ──
        ActivityProgress activities,

        // ── Engagement progress ──
        EngagementProgress engagement,

        // ── Personalized insights ──
        List<ProgressInsight> insights,

        // ── Metadata ──
        String dataAvailability,
        Instant generatedAt
) {
    /**
     * Mood progress computed from actual mood entries.
     */
    public record MoodProgress(
            int totalEntries,
            int entriesThisWeek,
            int currentStreak,
            int longestStreak,
            String dominantMood,
            String moodTrend,
            String moodTrendDescription,
            Map<String, Long> distribution,
            boolean hasData
    ) {}

    /**
     * Journal progress computed from actual journal entries and AI analysis.
     */
    public record JournalProgress(
            int totalEntries,
            int entriesThisWeek,
            String activityLevel,
            List<String> recentEmotions,
            boolean hasData
    ) {}

    /**
     * Activity progress computed from recommendation interactions.
     */
    public record ActivityProgress(
            int completedThisWeek,
            int totalCompleted,
            int helpfulCount,
            int dismissedCount,
            List<String> recentlyCompletedTitles,
            boolean hasData
    ) {}

    /**
     * Engagement progress computed from cross-feature activity.
     */
    public record EngagementProgress(
            int totalFeaturesUsed,
            int activeFeaturesThisWeek,
            int coachConversations,
            String consistencyLevel,
            String engagementSummary
    ) {}

    /**
     * A single personalized progress insight.
     */
    public record ProgressInsight(
            String type,
            String title,
            String description,
            String icon
    ) {}
}
