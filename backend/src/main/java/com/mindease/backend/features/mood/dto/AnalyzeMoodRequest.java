package com.mindease.backend.features.mood.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

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

    /**
     * On-device facial-expression observation. Legacy keys are required for
     * old clients; synora-fer clients additionally send the versioned keys
     * (status, calibratedConfidence, modelId, modelVersion,
     * preprocessingVersion). Unknown fields are ignored for forward
     * compatibility.
     */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record CameraObservation(
            String dominantEmotion,
            java.util.Map<String, Double> emotionScores,
            Boolean faceDetected,
            Integer faceCount,
            Double faceQuality,
            Double valence,
            Double arousal,
            Integer framesAnalyzed,
            String status,
            Double calibratedConfidence,
            String modelId,
            String modelVersion,
            String preprocessingVersion,
            String delegate,
            Integer processingLatencyMs) {

        /** Legacy 8-arg shape kept for existing callers/tests. */
        public CameraObservation(
                String dominantEmotion,
                java.util.Map<String, Double> emotionScores,
                Boolean faceDetected,
                Integer faceCount,
                Double faceQuality,
                Double valence,
                Double arousal,
                Integer framesAnalyzed) {
            this(dominantEmotion, emotionScores, faceDetected, faceCount,
                    faceQuality, valence, arousal, framesAnalyzed,
                    null, null, null, null, null, null, null);
        }
    }
}
