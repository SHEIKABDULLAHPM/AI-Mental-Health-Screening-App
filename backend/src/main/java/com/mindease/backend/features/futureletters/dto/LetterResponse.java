package com.mindease.backend.features.futureletters.dto;

import java.time.Instant;
import java.time.LocalDate;

import com.mindease.backend.features.futureletters.domain.FutureLetter;

public record LetterResponse(
        String id,
        String title,
        String recipient,
        String content,
        LocalDate scheduledDate,
        String status,
        Instant createdAt,
        Instant updatedAt) {

    public static LetterResponse from(FutureLetter letter) {
        return new LetterResponse(
                letter.getId(),
                letter.getTitle(),
                letter.getRecipient(),
                letter.getContent(),
                letter.getScheduledDate(),
                letter.getStatus(),
                letter.getCreatedAt(),
                letter.getUpdatedAt());
    }
}
