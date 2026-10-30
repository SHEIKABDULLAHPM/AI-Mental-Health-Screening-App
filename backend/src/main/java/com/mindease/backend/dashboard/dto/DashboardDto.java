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
        boolean safetyFlag,
        NotificationInfo notifications,
        List<String> navEntryPoints,
        PersonalizationSummary personalization,
        MoodSummary mood) {

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

    /**
     * Authoritative mood progress summary for the dashboard home tab.
     * Derived server-side from mood history via MoodService/MoodTrendAnalyzer —
     * the client must display it as-is and never recalculate the trend.
     * All fields except hasHistory are null when no history exists. Camera
     * fields come from the latest completed wellness profile (null while the
     * profile is pending or when no camera step was taken).
     */
    public record MoodSummary(
            boolean hasHistory,
            String currentMood,
            String moodEmotion,
            Integer moodScore,
            String trendDirection,
            String trendDescription,
            Integer historyCount,
            String cameraEmotion,
            String signalAgreement) {
        public static MoodSummary empty() {
            return new MoodSummary(false, null, null, null, "unknown",
                    "No mood history yet.", 0, null, null);
        }

        public MoodSummary withCamera(String cameraEmotion, String signalAgreement) {
            return new MoodSummary(hasHistory, currentMood, moodEmotion,
                    moodScore, trendDirection, trendDescription, historyCount,
                    cameraEmotion, signalAgreement);
        }
    }

    public static DashboardDto of(UserProfileDto user, String greetingName,
                                  WellnessProfileDto profile) {
        return of(user, greetingName, profile, null, null);
    }

    public static DashboardDto of(UserProfileDto user, String greetingName,
                                  WellnessProfileDto profile,
                                  PersonalizationSummary personalization) {
        return of(user, greetingName, profile, personalization, null);
    }

    public static DashboardDto of(UserProfileDto user, String greetingName,
                                  WellnessProfileDto profile,
                                  PersonalizationSummary personalization,
                                  MoodSummary mood) {
        boolean ready = profile != null && profile.status() == ProfileStatus.COMPLETED;
        return new DashboardDto(
                user,
                greetingName,
                ready,
                profile == null ? ProfileStatus.AI_ANALYSIS_PENDING.name() : profile.status().name(),
                ready ? profile.wellnessScore() : null,
                ready ? profile.aiInsight() : null,
                profile != null && Boolean.TRUE.equals(profile.safetyFlag()),
                new NotificationInfo(0),
                List.of("daily_check_in", "mood_tracking", "journal", "ai_coach",
                        "recommendations", "habit_tracker", "challenges", "reports",
                        "physical_wellness"),
                personalization,
                mood != null ? mood : MoodSummary.empty());
    }
}