package com.mindease.backend.features.challenges.dto;

import java.util.List;

/**
 * Aggregated payload for the Challenges home screen. Mirrors what the UI needs
 * without exposing raw internal entities.
 */
public record ChallengeHomeResponse(
        List<ChallengeResponse> active,
        List<ChallengeResponse> completed,
        List<BadgeResponse> badges,
        int currentStreak,
        int pointsEarned,
        ChallengeResponse recommended) {
}
