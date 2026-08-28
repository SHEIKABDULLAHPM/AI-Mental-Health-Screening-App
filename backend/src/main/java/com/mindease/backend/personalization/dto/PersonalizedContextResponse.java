package com.mindease.backend.personalization.dto;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import com.mindease.backend.personalization.domain.PersonalizedContext;

/**
 * API response DTO for the personalized context.
 * Exposes only derived signals — never raw private data.
 */
public record PersonalizedContextResponse(
        // Mood
        String currentMood,
        String currentEmotion,
        String moodTrend,
        String moodTrendDescription,
        Map<String, Long> moodDistribution,
        int moodEntryCount,
        long hoursSinceLastCheckin,
        String dominantMood,

        // Journal
        boolean journalAvailable,
        List<String> journalEmotionalThemes,
        List<String> journalSentiments,
        int recentJournalCount,
        String journalActivityLevel,

        // Recommendations
        int recentlyCompletedCount,
        int recentlyDismissedCount,
        List<String> helpfulRecommendations,
        List<String> notUsefulRecommendations,

        // Coach
        boolean coachActive,
        List<String> coachTopics,
        List<String> coachMemoryCategories,

        // Wellness
        String stressLevel,
        String sleepQuality,
        String primaryFocus,
        Integer wellnessScore,

        // Derived
        List<String> emotionalThemes,
        Map<String, String> preferenceSignals,
        String personalizationSummary,

        // Metadata
        String contextVersion,
        Instant generatedAt,
        Instant expiresAt
) {
    public static PersonalizedContextResponse from(PersonalizedContext ctx) {
        return new PersonalizedContextResponse(
                ctx.getCurrentMood(),
                ctx.getCurrentEmotion(),
                ctx.getMoodTrend(),
                ctx.getMoodTrendDescription(),
                ctx.getMoodDistribution(),
                ctx.getMoodEntryCount(),
                ctx.getHoursSinceLastCheckin(),
                ctx.getDominantMood(),
                ctx.isJournalAvailable(),
                ctx.getJournalEmotionalThemes(),
                ctx.getJournalSentiments(),
                ctx.getRecentJournalCount(),
                ctx.getJournalActivityLevel(),
                ctx.getRecentlyCompletedRecommendations() != null
                        ? ctx.getRecentlyCompletedRecommendations().size() : 0,
                ctx.getRecentlyDismissedRecommendations() != null
                        ? ctx.getRecentlyDismissedRecommendations().size() : 0,
                ctx.getHelpfulRecommendations(),
                ctx.getNotUsefulRecommendations(),
                ctx.isCoachActive(),
                ctx.getCoachTopics(),
                ctx.getCoachMemoryCategories(),
                ctx.getStressLevel(),
                ctx.getSleepQuality(),
                ctx.getPrimaryFocus(),
                ctx.getWellnessScore(),
                ctx.getEmotionalThemes(),
                ctx.getPreferenceSignals(),
                ctx.getPersonalizationSummary(),
                ctx.getContextVersion(),
                ctx.getGeneratedAt(),
                ctx.getExpiresAt()
        );
    }
}
