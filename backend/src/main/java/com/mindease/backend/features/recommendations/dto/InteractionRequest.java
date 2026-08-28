package com.mindease.backend.features.recommendations.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * Interaction tracking request.
 * Valid values: SHOWN, OPENED, STARTED, COMPLETED
 */
public record InteractionRequest(
        @NotBlank String interactionType,
        String requestId
) {
}
