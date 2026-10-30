package com.mindease.backend.features.challenges.dto;

import java.time.Instant;

/**
 * A badge a user has earned. Deterministic and idempotent.
 */
public record BadgeResponse(
        String code,
        String label,
        String challengeId,
        Instant earnedAt) {
}
