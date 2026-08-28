package com.mindease.backend.features.mood.dto;

import java.time.Instant;
import java.util.List;

import com.mindease.backend.features.mood.domain.MoodEntry;

public record MoodResponse(
        String id,
        String mood,
        String emotion,
        String note,
        Instant recordedAt,
        Instant createdAt,
        Instant updatedAt,
        String source,
        Double confidence,
        String analysisStatus,
        List<AiObservationDto> aiObservations,
        String aiSuggestedMood,
        Integer intensity) {

    public record AiObservationDto(
            String source,
            String emotion,
            Double confidence,
            String sentiment,
            Double sentimentConfidence,
            String suggestedMood,
            String modelVersion) {

        public static AiObservationDto from(MoodEntry.AiObservation obs) {
            return new AiObservationDto(
                    obs.getSource(),
                    obs.getEmotion(),
                    obs.getConfidence(),
                    obs.getSentiment(),
                    obs.getSentimentConfidence(),
                    obs.getSuggestedMood(),
                    obs.getModelVersion());
        }
    }

    public static MoodResponse from(MoodEntry entity) {
        List<AiObservationDto> observations = entity.getAiObservations() != null
                ? entity.getAiObservations().stream()
                        .map(AiObservationDto::from)
                        .toList()
                : List.of();

        return new MoodResponse(
                entity.getId(),
                entity.getMood(),
                entity.getEmotion(),
                entity.getNote(),
                entity.getRecordedAt(),
                entity.getCreatedAt(),
                entity.getUpdatedAt(),
                entity.getSource(),
                entity.getConfidence(),
                entity.getAnalysisStatus(),
                observations,
                entity.getAiSuggestedMood(),
                entity.getIntensity());
    }
}
