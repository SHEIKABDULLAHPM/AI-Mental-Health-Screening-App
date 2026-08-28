package com.mindease.backend.features.habits.dto;

public record UpdateHabitRequest(
        String title,
        Integer iconCodePoint,
        Long colorValue,
        String goalLabel,
        String unit) {
}
