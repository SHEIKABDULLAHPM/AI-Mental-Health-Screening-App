package com.mindease.backend.features.challenges.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/**
 * Structured game result submitted by the Flutter client after a legitimate
 * game completion. The backend validates these fields against deterministic
 * game rules before advancing challenge progress.
 *
 * <p>Game opening is NOT completion. A valid result is emitted only after
 * the game's legitimate completion condition is reached.</p>
 */
public record GameResultRequest(
        @NotBlank(message = "Game type is required")
        String gameType,

        @NotNull(message = "Score is required")
        @Min(value = 0, message = "Score cannot be negative")
        int score,

        boolean completed,

        @Min(value = 0, message = "Moves cannot be negative")
        int moves,

        @Min(value = 0, message = "Duration cannot be negative")
        int durationSeconds,

        String difficulty
) {
}
