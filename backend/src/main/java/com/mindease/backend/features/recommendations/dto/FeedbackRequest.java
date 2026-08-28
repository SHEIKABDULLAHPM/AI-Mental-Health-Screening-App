package com.mindease.backend.features.recommendations.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * Feedback request for a recommendation.
 * Valid values: HELPFUL, NOT_USEFUL, ALREADY_COMPLETED, DISMISSED
 */
public record FeedbackRequest(
        @NotBlank String feedbackType,
        String requestId
) {
}
