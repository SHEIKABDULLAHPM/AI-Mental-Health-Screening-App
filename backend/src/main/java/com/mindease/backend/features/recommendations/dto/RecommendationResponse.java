package com.mindease.backend.features.recommendations.dto;

import java.time.Instant;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Response DTO for a personalized recommendation.
 * Only returns safe, non-sensitive information.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record RecommendationResponse(
        String id,
        String title,
        String description,
        String category,
        String type,
        String reason,       // "Why this?" - personalized explanation
        String duration,
        String difficulty,
        String contentReference,
        int contentVersion,
        Instant generatedAt
) {
}
