package com.mindease.backend.features.emotion.domain;

import java.time.Instant;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Immutable facial-expression observation emitted on-device by vit-fer-7.
 *
 * Derived data only: canonical emotion id, class scores, calibrated
 * confidence, face quality and model provenance. Raw face images are never
 * stored. userId always comes from the authenticated JWT, never the client.
 */
@Document(collection = "emotion_events")
@CompoundIndexes({
        @CompoundIndex(name = "user_captured_idx", def = "{'userId': 1, 'capturedAt': -1}"),
        @CompoundIndex(name = "user_emotion_captured_idx", def = "{'userId': 1, 'emotion': 1, 'capturedAt': -1}"),
        @CompoundIndex(name = "uq_user_idempotency", def = "{'userId': 1, 'idempotencyKey': 1}", unique = true)
})
public class EmotionEvent {

    @Id
    private String id;

    @Indexed
    private String userId;

    /** Canonical emotion id (anger, disgust, fear, happy, neutral, sad, surprise) or "unknown". */
    private String emotion;

    /** Per-class calibrated probabilities, keyed by canonical class. */
    private Map<String, Double> scores;

    /** Calibrated confidence of the top class (0.0-1.0). */
    private Double calibratedConfidence;

    /** Face quality gate score (0.0-1.0). */
    private Double faceQuality;

    /** Model identity, e.g. "vit-fer-7". */
    private String modelId;

    /** Model version, e.g. "1.0.0". */
    private String modelVersion;

    /** Preprocessing contract version, e.g. "1.0.0". */
    private String preprocessingVersion;

    /** Event status wire value: PREDICTED, UNCERTAIN, or a quality-gate status. */
    private String status;

    /** Capture source: CAMERA (only supported source in v1). */
    private String source;

    /** Device capture timestamp. */
    private Instant capturedAt;

    private Instant createdAt;

    /** Client idempotency key; replays return the original event. */
    private String idempotencyKey;

    public EmotionEvent() {
    }

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

    public String getEmotion() {
        return emotion;
    }

    public void setEmotion(String emotion) {
        this.emotion = emotion;
    }

    public Map<String, Double> getScores() {
        return scores;
    }

    public void setScores(Map<String, Double> scores) {
        this.scores = scores;
    }

    public Double getCalibratedConfidence() {
        return calibratedConfidence;
    }

    public void setCalibratedConfidence(Double calibratedConfidence) {
        this.calibratedConfidence = calibratedConfidence;
    }

    public Double getFaceQuality() {
        return faceQuality;
    }

    public void setFaceQuality(Double faceQuality) {
        this.faceQuality = faceQuality;
    }

    public String getModelId() {
        return modelId;
    }

    public void setModelId(String modelId) {
        this.modelId = modelId;
    }

    public String getModelVersion() {
        return modelVersion;
    }

    public void setModelVersion(String modelVersion) {
        this.modelVersion = modelVersion;
    }

    public String getPreprocessingVersion() {
        return preprocessingVersion;
    }

    public void setPreprocessingVersion(String preprocessingVersion) {
        this.preprocessingVersion = preprocessingVersion;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public Instant getCapturedAt() {
        return capturedAt;
    }

    public void setCapturedAt(Instant capturedAt) {
        this.capturedAt = capturedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public String getIdempotencyKey() {
        return idempotencyKey;
    }

    public void setIdempotencyKey(String idempotencyKey) {
        this.idempotencyKey = idempotencyKey;
    }
}
