package com.mindease.backend.features.journal.dto;

import jakarta.validation.constraints.Size;

public record UpdateJournalRequest(
        @Size(min = 1, max = 500) String title,
        @Size(min = 0, max = 50000) String content,
        String type,
        String emotion,
        String imageKey,
        String imageContentType,
        Long imageSize,
        String audioKey,
        String audioContentType,
        Long audioSize,
        Integer audioDurationSeconds,
        String videoKey,
        String videoContentType,
        Long videoSize,
        Integer videoDurationSeconds,
        Boolean removeImage,
        Boolean removeAudio,
        Boolean removeVideo) {
}
