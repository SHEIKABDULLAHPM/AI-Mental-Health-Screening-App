package com.mindease.backend.features.mood.dto;

import java.time.Instant;
import java.util.List;
import java.util.Set;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record CreateMoodRequest(
        @NotBlank @Pattern(regexp = "^(very_happy|happy|calm|okay|low|stressed)$",
                message = "Mood must be one of: very_happy, happy, calm, okay, low, stressed") String mood,
        @Size(max = 100) String emotion,
        @Size(max = 5000) String note,
        Instant recordedAt,
        @Pattern(regexp = "^(MANUAL|CAMERA|TEXT|MULTIMODAL|CAMERA_AND_TEXT)$",
                message = "Source must be one of: MANUAL, CAMERA, TEXT, MULTIMODAL, CAMERA_AND_TEXT") String source,
        List<AiObservationInput> aiObservations,
        Double confidence,
        String aiSuggestedMood,
        Integer intensity) {

    private static final Set<String> VALID_SOURCES = Set.of(
            "MANUAL", "CAMERA", "TEXT", "MULTIMODAL", "CAMERA_AND_TEXT");

    public CreateMoodRequest {
        if (source != null && !VALID_SOURCES.contains(source)) {
            throw new IllegalArgumentException(
                    "Source must be one of: MANUAL, CAMERA, TEXT, MULTIMODAL, CAMERA_AND_TEXT");
        }
        if (confidence != null && (confidence < 0.0 || confidence > 1.0)) {
            throw new IllegalArgumentException("Confidence must be between 0.0 and 1.0");
        }
        if (intensity != null && (intensity < 1 || intensity > 10)) {
            throw new IllegalArgumentException("Intensity must be between 1 and 10");
        }
    }

    public record AiObservationInput(
            String source,
            String emotion,
            Double confidence,
            String sentiment,
            Double sentimentConfidence,
            String suggestedMood,
            String modelVersion) {

        public AiObservationInput {
            if (confidence != null && (confidence < 0.0 || confidence > 1.0)) {
                throw new IllegalArgumentException("AI observation confidence must be between 0.0 and 1.0");
            }
            if (sentimentConfidence != null && (sentimentConfidence < 0.0 || sentimentConfidence > 1.0)) {
                throw new IllegalArgumentException("Sentiment confidence must be between 0.0 and 1.0");
            }
        }
    }
}
