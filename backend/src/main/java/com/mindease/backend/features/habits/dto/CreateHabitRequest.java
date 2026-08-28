package com.mindease.backend.features.habits.dto;

import jakarta.validation.constraints.NotBlank;

public record CreateHabitRequest(
        @NotBlank String title,
        Integer iconCodePoint,
        Long colorValue,
        @NotBlank String goalLabel,
        String unit) {
}
