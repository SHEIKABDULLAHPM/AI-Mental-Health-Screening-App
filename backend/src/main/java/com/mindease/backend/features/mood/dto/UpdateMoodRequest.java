package com.mindease.backend.features.mood.dto;

import java.util.Set;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record UpdateMoodRequest(
        @Pattern(regexp = "^(very_happy|happy|calm|okay|low|stressed)$",
                message = "Mood must be one of: very_happy, happy, calm, okay, low, stressed") String mood,
        @Size(max = 100) String emotion,
        @Size(max = 5000) String note,
        Integer intensity) {

    private static final Set<String> VALID_MOODS = Set.of(
            "very_happy", "happy", "calm", "okay", "low", "stressed");

    public UpdateMoodRequest {
        if (mood != null && !VALID_MOODS.contains(mood)) {
            throw new IllegalArgumentException(
                    "Mood must be one of: very_happy, happy, calm, okay, low, stressed");
        }
        if (intensity != null && (intensity < 1 || intensity > 10)) {
            throw new IllegalArgumentException("Intensity must be between 1 and 10");
        }
    }
}
