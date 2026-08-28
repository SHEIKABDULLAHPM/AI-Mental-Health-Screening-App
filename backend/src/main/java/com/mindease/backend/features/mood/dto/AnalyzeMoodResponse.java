package com.mindease.backend.features.mood.dto;

import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Response from the AI mood analysis service.
 * Contains fused multimodal result with source preservation,
 * trend analysis, wellness guidance, safety check, and reflection prompt.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record AnalyzeMoodResponse(
        @JsonProperty("fused_mood") String fusedMood,
        @JsonProperty("fused_emotion") String fusedEmotion,
        @JsonProperty("confidence") Double confidence,
        @JsonProperty("sources_used") List<String> sourcesUsed,
        @JsonProperty("manual_mood") String manualMood,
        @JsonProperty("text_analysis") TextAnalysisResult textAnalysis,
        @JsonProperty("camera_analysis") CameraAnalysisResult cameraAnalysis,
        @JsonProperty("needs_confirmation") Boolean needsConfirmation,
        @JsonProperty("model_version") String modelVersion,
        @JsonProperty("trend") TrendResult trend,
        @JsonProperty("guidance") GuidanceResult guidance,
        @JsonProperty("safety") SafetyResult safety,
        @JsonProperty("reflection") ReflectionResult reflection) {

    public record TextAnalysisResult(
            @JsonProperty("source") String source,
            @JsonProperty("emotion") String emotion,
            @JsonProperty("emotion_confidence") Double emotionConfidence,
            @JsonProperty("sentiment") String sentiment,
            @JsonProperty("sentiment_confidence") Double sentimentConfidence,
            @JsonProperty("suggested_mood") String suggestedMood,
            @JsonProperty("model_version") String modelVersion) {
    }

    public record CameraAnalysisResult(
            @JsonProperty("source") String source,
            @JsonProperty("emotion") String emotion,
            @JsonProperty("confidence") Double confidence,
            @JsonProperty("suggested_mood") String suggestedMood,
            @JsonProperty("face_quality") Double faceQuality,
            @JsonProperty("frames_analyzed") Integer framesAnalyzed,
            @JsonProperty("model_version") String modelVersion) {
    }

    public record TrendResult(
            @JsonProperty("direction") String direction,
            @JsonProperty("description") String description,
            @JsonProperty("data_points") Integer dataPoints) {
    }

    public record GuidanceResult(
            @JsonProperty("message") String message,
            @JsonProperty("actions") List<Map<String, String>> actions,
            @JsonProperty("safety_flag") Boolean safetyFlag) {
    }

    public record SafetyResult(
            @JsonProperty("flag") Boolean flag,
            @JsonProperty("level") String level,
            @JsonProperty("message") String message,
            @JsonProperty("resources") Map<String, String> resources) {
    }

    public record ReflectionResult(
            @JsonProperty("text") String text,
            @JsonProperty("mood_context") String moodContext,
            @JsonProperty("type") String type) {
    }
}
