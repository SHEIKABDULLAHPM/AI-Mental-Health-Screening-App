package com.mindease.backend.features.futureletters.dto;

import java.time.LocalDate;

import jakarta.validation.constraints.Future;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record CreateLetterRequest(
        @NotBlank String title,
        String recipient,
        @NotBlank String content,
        @NotNull @Future LocalDate scheduledDate) {
}
