package com.mindease.backend.features.emotion.dto;

import java.time.Instant;
import java.util.Map;

import com.mindease.backend.features.emotion.domain.EmotionEvent;

public record EmotionEventResponse(
        String id,
        String emotion,
        Map<String, Double> scores,
        Double calibratedConfidence,
        Double faceQuality,
        String modelId,
        String modelVersion,
        String preprocessingVersion,
        String status,
        String source,
        Instant capturedAt,
        Instant createdAt) {

    public static EmotionEventResponse from(EmotionEvent e) {
        return new EmotionEventResponse(
                e.getId(), e.getEmotion(), e.getScores(), e.getCalibratedConfidence(),
                e.getFaceQuality(), e.getModelId(), e.getModelVersion(),
                e.getPreprocessingVersion(), e.getStatus(), e.getSource(),
                e.getCapturedAt(), e.getCreatedAt());
    }
}
