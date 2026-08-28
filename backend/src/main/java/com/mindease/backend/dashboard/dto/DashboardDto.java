package com.mindease.backend.dashboard.dto;

import java.util.List;

import com.mindease.backend.user.dto.UserProfileDto;
import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

/**
 * Aggregate payload for the Dashboard screen. AI-derived values stay null and
 * {@code aiReady} stays false while the profile is AI_ANALYSIS_PENDING — the
 * client shows a pending state instead of invented numbers.
 */
public record DashboardDto(
        UserProfileDto user,
        String greetingName,
        boolean aiReady,
        String aiStatus,
        Integer wellnessScore,
        String todayInsight,
        NotificationInfo notifications,
        List<String> navEntryPoints,
        PersonalizationSummary personalization) {

    public record NotificationInfo(int unreadCount) {
    }

    /**
     * Lightweight personalization summary for the dashboard.
     * Never exposes raw data or internal scores.
     */
    public record PersonalizationSummary(
            String currentMood,
            String moodTrend,
            String dominantMood,
            boolean journalAvailable,
            int recentJournalCount,
            String summary
    ) {}

    public static DashboardDto of(UserProfileDto user, String greetingName,
                                  WellnessProfileDto profile) {
        return of(user, greetingName, profile, null);
    }

    public static DashboardDto of(UserProfileDto user, String greetingName,
                                  WellnessProfileDto profile,
                                  PersonalizationSummary personalization) {
        boolean ready = profile != null && profile.status() == ProfileStatus.COMPLETED;
        return new DashboardDto(
                user,
                greetingName,
                ready,
                profile == null ? ProfileStatus.AI_ANALYSIS_PENDING.name() : profile.status().name(),
                ready ? profile.wellnessScore() : null,
                ready ? profile.aiInsight() : null,
                new NotificationInfo(0),
                List.of("daily_check_in", "mood_tracking", "journal", "ai_coach",
                        "recommendations", "habit_tracker", "challenges", "reports"),
                personalization);
    }
}