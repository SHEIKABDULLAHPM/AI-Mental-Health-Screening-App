package com.mindease.backend.features.emotion.dto;

import java.time.Instant;
import java.util.Map;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import com.mindease.backend.features.emotion.domain.EmotionClasses;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Client-submitted facial-expression observation. Every field is validated
 * server-side; userId is never accepted from the client.
 */
public record CreateEmotionEventRequest(
        @NotBlank @Pattern(regexp = EmotionClasses.PATTERN,
                message = "emotion must be a canonical vit-fer-7 class or unknown") String emotion,
        @NotNull @Size(min = EmotionClasses.COUNT, max = EmotionClasses.COUNT,
                message = "scores must cover all 7 canonical classes") Map<String, Double> scores,
        @NotNull @DecimalMin("0.0") @DecimalMax("1.0") Double calibratedConfidence,
        @NotNull @DecimalMin("0.0") @DecimalMax("1.0") Double faceQuality,
        @NotBlank @Size(max = 64) String modelId,
        @NotBlank @Size(max = 32) String modelVersion,
        @NotBlank @Size(max = 32) String preprocessingVersion,
        @NotBlank @Pattern(regexp = "PREDICTED|UNCERTAIN|NO_FACE|MULTIPLE_FACES|FACE_TOO_SMALL|FACE_TOO_BLURRY|FACE_OCCLUDED|BAD_LIGHTING|BAD_POSE",
                message = "status must be a vit-fer-7 wire status") String status,
        @NotBlank @Pattern(regexp = "CAMERA", message = "source must be CAMERA") String source,
        @NotNull Instant capturedAt,
        @NotBlank @Size(min = 8, max = 128) String idempotencyKey) {
}
