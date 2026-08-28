package com.mindease.backend.features.habits.dto;

import java.time.LocalDate;

import jakarta.validation.constraints.NotNull;

public record HabitRecordRequest(
        @NotNull LocalDate date,
        boolean completed) {
}
