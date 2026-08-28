package com.mindease.backend.features.mood.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Request to analyze mood via the AI service.
 * The backend proxies this to the Python AI service and returns structured results.
 */
public record AnalyzeMoodRequest(
        @NotBlank String mood,
        String emotion,
        @Size(max = 5000) String note,
        CameraObservation cameraObservation) {

    public record CameraObservation(
            String dominantEmotion,
            java.util.Map<String, Double> emotionScores,
            Boolean faceDetected,
            Integer faceCount,
            Double faceQuality,
            Double valence,
            Double arousal,
            Integer framesAnalyzed) {
    }
}
