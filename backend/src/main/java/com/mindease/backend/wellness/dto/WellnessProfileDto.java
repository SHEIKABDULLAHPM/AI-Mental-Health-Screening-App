package com.mindease.backend.wellness.dto;

import java.time.Instant;

import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.domain.WellnessProfile;

/**
 * Safe projection of the wellness profile. AI-derived fields are null while
 * the status is {@code AI_ANALYSIS_PENDING}.
 */
public record WellnessProfileDto(
        String id,
        String assessmentId,
        ProfileStatus status,
        Integer wellnessScore,
        String stressLevel,
        Integer lifestyleScore,
        String sleepQuality,
        String primaryFocus,
        String aiInsight,
        String moodMood,
        String moodEmotion,
        Integer moodIntensity,
        Integer moodScore,
        String moodTrendDirection,
        String moodTrendDescription,
        Integer moodHistoryCount,
        String cameraEmotion,
        Double cameraConfidence,
        String signalAgreement,
        Boolean safetyFlag,
        Instant createdAt,
        Instant updatedAt) {

    public static WellnessProfileDto from(WellnessProfile profile) {
        return new WellnessProfileDto(
                profile.getId(),
                profile.getAssessmentId(),
                profile.getStatus(),
                profile.getWellnessScore(),
                profile.getStressLevel(),
                profile.getLifestyleScore(),
                profile.getSleepQuality(),
                profile.getPrimaryFocus(),
                profile.getAiInsight(),
                profile.getMoodMood(),
                profile.getMoodEmotion(),
                profile.getMoodIntensity(),
                profile.getMoodScore(),
                profile.getMoodTrendDirection(),
                profile.getMoodTrendDescription(),
                profile.getMoodHistoryCount(),
                profile.getCameraEmotion(),
                profile.getCameraConfidence(),
                profile.getSignalAgreement(),
                profile.getSafetyFlag(),
                profile.getCreatedAt(),
                profile.getUpdatedAt());
    }
}