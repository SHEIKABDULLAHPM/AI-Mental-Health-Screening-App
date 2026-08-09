package com.mindease.backend.modules.screening.domain;

import java.time.Instant;

import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Domain aggregate for a mental-health screening session (PHQ-9, GAD-7, ...).
 * Placeholder - extend as questionnaires are implemented.
 */
@Document(collection = "screenings")
public record Screening(
        @Id String id,
        String userId,
        String questionnaireType,
        int totalScore,
        @CreatedDate Instant createdAt) {

    public Screening {
        createdAt = createdAt == null ? Instant.now() : createdAt;
    }
}