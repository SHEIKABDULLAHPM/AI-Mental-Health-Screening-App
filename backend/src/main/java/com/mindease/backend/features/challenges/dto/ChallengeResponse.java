package com.mindease.backend.features.challenges.dto;

import java.time.Instant;

/**
 * A challenge's definition combined with the requesting user's current progress.
 * This is a plain DTO (never a MongoDB entity).
 */
public record ChallengeResponse(
        String id,
        String title,
        String description,
        String why,
        String type,
        String frequency,
        String category,
        String difficulty,
        String estimatedDuration,
        int target,
        int durationDays,
        int points,
        String reward,
        String badgeCode,
        String status,
        int progress,
        int remaining,
        double percentage,
        int streak,
        int bestStreak,
        int attempts,
        Instant startedAt,
        Instant expiresAt,
        Instant completedAt,
        String personalizationReason) {

    public static ChallengeResponse fromDomain(
            com.mindease.backend.features.challenges.domain.Challenge c,
            com.mindease.backend.features.challenges.domain.UserChallenge uc,
            String personalizationReason) {

        int progress = uc != null ? uc.getProgress() : 0;
        int target = (uc != null && uc.getTarget() > 0) ? uc.getTarget() : c.getTarget();
        String status = uc != null ? uc.getStatus()
                : (c.isActive() ? "AVAILABLE" : "EXPIRED");
        double percentage = target <= 0 ? 0.0
                : Math.min(100.0 * progress / target, 100.0);
        int remaining = Math.max(target - progress, 0);

        boolean started = uc != null && uc.getStartedAt() != null;
        boolean completed = uc != null && "COMPLETED".equals(status);

        return new ChallengeResponse(
                c.getId(),
                c.getTitle(),
                c.getDescription(),
                c.getWhy(),
                c.getType(),
                c.getFrequency(),
                c.getCategory(),
                c.getDifficulty(),
                c.getEstimatedDuration(),
                target,
                c.getDurationDays(),
                c.getPoints(),
                c.getReward(),
                c.getBadgeCode(),
                status,
                progress,
                remaining,
                Math.round(percentage * 100.0) / 100.0,
                uc != null ? uc.getStreak() : 0,
                uc != null ? uc.getBestStreak() : 0,
                uc != null ? uc.getAttempts() : 0,
                started ? uc.getStartedAt() : null,
                uc != null ? uc.getExpiresAt() : null,
                completed ? uc.getCompletedAt() : null,
                personalizationReason);
    }
}
