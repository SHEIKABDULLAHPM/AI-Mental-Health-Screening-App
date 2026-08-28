package com.mindease.backend.features.journal.dto;

import java.time.Instant;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.mindease.backend.features.journal.domain.JournalEntry;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record JournalResponse(
        String id,
        String title,
        String content,
        String type,
        String emotion,
        // Media
        String imageKey,
        String imageContentType,
        Long imageSize,
        String imageUrl,
        String audioKey,
        String audioContentType,
        Long audioSize,
        Integer audioDurationSeconds,
        String audioUrl,
        String videoKey,
        String videoContentType,
        Long videoSize,
        Integer videoDurationSeconds,
        String videoUrl,
        // AI analysis
        AiAnalysisDto aiAnalysis,
        // Versioning
        int contentVersion,
        Instant createdAt,
        Instant updatedAt) {

    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record AiAnalysisDto(
            String status,
            String emotion,
            Double emotionConfidence,
            String sentiment,
            Double sentimentConfidence,
            String emotionalThemes,
            String summary,
            String reflectionPrompt,
            String analysisVersion,
            Integer analyzedContentVersion,
            Instant analyzedAt) {

        public static AiAnalysisDto from(JournalEntry.AiAnalysis ai) {
            if (ai == null) return null;
            return new AiAnalysisDto(
                    ai.getStatus(),
                    ai.getEmotion(),
                    ai.getEmotionConfidence(),
                    ai.getSentiment(),
                    ai.getSentimentConfidence(),
                    ai.getEmotionalThemes(),
                    ai.getSummary(),
                    ai.getReflectionPrompt(),
                    ai.getAnalysisVersion(),
                    ai.getAnalyzedContentVersion(),
                    ai.getAnalyzedAt());
        }
    }

    public static JournalResponse from(JournalEntry entry, String imageUrl, String audioUrl, String videoUrl) {
        return new JournalResponse(
                entry.getId(),
                entry.getTitle(),
                entry.getContent(),
                entry.getType(),
                entry.getEmotion(),
                entry.getImageKey(),
                entry.getImageContentType(),
                entry.getImageSize(),
                imageUrl,
                entry.getAudioKey(),
                entry.getAudioContentType(),
                entry.getAudioSize(),
                entry.getAudioDurationSeconds(),
                audioUrl,
                entry.getVideoKey(),
                entry.getVideoContentType(),
                entry.getVideoSize(),
                entry.getVideoDurationSeconds(),
                videoUrl,
                AiAnalysisDto.from(entry.getAiAnalysis()),
                entry.getContentVersion(),
                entry.getCreatedAt(),
                entry.getUpdatedAt());
    }

    /** Convenience factory without URL resolution (for testing). */
    public static JournalResponse from(JournalEntry entry) {
        return from(entry, null, null, null);
    }
}
