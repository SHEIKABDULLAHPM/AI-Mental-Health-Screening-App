package com.mindease.backend.features.futureletters.dto;

import java.time.LocalDate;

import jakarta.validation.constraints.Size;

public record UpdateLetterRequest(
        @Size(min = 1, max = 500) String title,
        String recipient,
        @Size(min = 1, max = 10000) String content,
        LocalDate scheduledDate) {
}
