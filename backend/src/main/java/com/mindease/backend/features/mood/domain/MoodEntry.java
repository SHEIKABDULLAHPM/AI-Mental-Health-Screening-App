package com.mindease.backend.features.mood.domain;

import java.time.Instant;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "mood_entries")
@CompoundIndex(name = "user_recorded_idx", def = "{'userId': 1, 'recordedAt': -1}")
public class MoodEntry {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String mood;

    private String emotion;

    private String note;

    private Instant recordedAt;

    private Instant createdAt;

    private Instant updatedAt;

    // ── AI observation fields ─────────────────────────────────────────

    /** Source of the mood entry: MANUAL, TEXT, CAMERA, or MULTIMODAL. */
    private String source;

    /** Confidence score (0.0–1.0) from AI analysis. Null for pure manual entries. */
    private Double confidence;

    /** Analysis status: NONE, COMPLETED, FAILED, PENDING. */
    private String analysisStatus;

    /** Structured AI observations from text/camera/fusion analysis. */
    private List<AiObservation> aiObservations;

    /** Suggested mood from AI fusion (may differ from user-confirmed mood). */
    private String aiSuggestedMood;

    /** Intensity of the mood (1–10 scale). Null for entries without explicit intensity. */
    private Integer intensity;

    // ── Constructors ──────────────────────────────────────────────────

    public MoodEntry() {
    }

    // ── Getters and Setters ───────────────────────────────────────────

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getMood() {
        return mood;
    }

    public void setMood(String mood) {
        this.mood = mood;
    }

    public String getEmotion() {
        return emotion;
    }

    public void setEmotion(String emotion) {
        this.emotion = emotion;
    }

    public String getNote() {
        return note;
    }

    public void setNote(String note) {
        this.note = note;
    }

    public Instant getRecordedAt() {
        return recordedAt;
    }

    public void setRecordedAt(Instant recordedAt) {
        this.recordedAt = recordedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public Double getConfidence() {
        return confidence;
    }

    public void setConfidence(Double confidence) {
        this.confidence = confidence;
    }

    public String getAnalysisStatus() {
        return analysisStatus;
    }

    public void setAnalysisStatus(String analysisStatus) {
        this.analysisStatus = analysisStatus;
    }

    public List<AiObservation> getAiObservations() {
        return aiObservations;
    }

    public void setAiObservations(List<AiObservation> aiObservations) {
        this.aiObservations = aiObservations;
    }

    public String getAiSuggestedMood() {
        return aiSuggestedMood;
    }

    public void setAiSuggestedMood(String aiSuggestedMood) {
        this.aiSuggestedMood = aiSuggestedMood;
    }

    public Integer getIntensity() {
        return intensity;
    }

    public void setIntensity(Integer intensity) {
        this.intensity = intensity;
    }

    // ── Embedded AI Observation ───────────────────────────────────────

    public static class AiObservation {

        private String source;
        private String emotion;
        private Double confidence;
        private String sentiment;
        private Double sentimentConfidence;
        private String suggestedMood;
        private String modelVersion;

        public AiObservation() {
        }

        public AiObservation(String source, String emotion, Double confidence) {
            this.source = source;
            this.emotion = emotion;
            this.confidence = confidence;
        }

        public String getSource() {
            return source;
        }

        public void setSource(String source) {
            this.source = source;
        }

        public String getEmotion() {
            return emotion;
        }

        public void setEmotion(String emotion) {
            this.emotion = emotion;
        }

        public Double getConfidence() {
            return confidence;
        }

        public void setConfidence(Double confidence) {
            this.confidence = confidence;
        }

        public String getSentiment() {
            return sentiment;
        }

        public void setSentiment(String sentiment) {
            this.sentiment = sentiment;
        }

        public Double getSentimentConfidence() {
            return sentimentConfidence;
        }

        public void setSentimentConfidence(Double sentimentConfidence) {
            this.sentimentConfidence = sentimentConfidence;
        }

        public String getSuggestedMood() {
            return suggestedMood;
        }

        public void setSuggestedMood(String suggestedMood) {
            this.suggestedMood = suggestedMood;
        }

        public String getModelVersion() {
            return modelVersion;
        }

        public void setModelVersion(String modelVersion) {
            this.modelVersion = modelVersion;
        }
    }
}
