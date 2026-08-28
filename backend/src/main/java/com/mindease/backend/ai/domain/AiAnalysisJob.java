package com.mindease.backend.ai.domain;

import java.time.Instant;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * An asynchronous AI analysis job created when a completed assessment is
 * submitted. The deterministic wellness analysis is computed by the backend at
 * submission and snapshotted on the job; the AI service consumes the queued
 * job, generates the LLM insight and posts the structured result back.
 */
@Document(collection = "ai_analysis_jobs")
public class AiAnalysisJob {

    @Id
    private String id;

    @Indexed
    private String userId;

    /** One AI job per assessment - the unique guard against duplicate jobs. */
    @Indexed(unique = true, name = "uq_assessment_id")
    private String assessmentId;

    private AiJobStatus status = AiJobStatus.QUEUED;

    private int attemptCount = 0;

    private int maxAttempts = 3;

    private String errorMessage;

    /** Deterministic analysis snapshot used as the AI service input. */
    private DeterministicScores scores;

    /** Structured result produced by the AI service. */
    private String aiInsight;

    private List<String> evidenceSources = List.of();

    private Instant createdAt;

    private Instant startedAt;

    private Instant completedAt;

    private Instant updatedAt;

    public AiAnalysisJob() {
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

    public String getAssessmentId() {
        return assessmentId;
    }

    public void setAssessmentId(String assessmentId) {
        this.assessmentId = assessmentId;
    }

    public AiJobStatus getStatus() {
        return status;
    }

    public void setStatus(AiJobStatus status) {
        this.status = status;
    }

    public int getAttemptCount() {
        return attemptCount;
    }

    public void setAttemptCount(int attemptCount) {
        this.attemptCount = attemptCount;
    }

    public int getMaxAttempts() {
        return maxAttempts;
    }

    public void setMaxAttempts(int maxAttempts) {
        this.maxAttempts = maxAttempts;
    }

    public String getErrorMessage() {
        return errorMessage;
    }

    public void setErrorMessage(String errorMessage) {
        this.errorMessage = errorMessage;
    }

    public DeterministicScores getScores() {
        return scores;
    }

    public void setScores(DeterministicScores scores) {
        this.scores = scores;
    }

    public String getAiInsight() {
        return aiInsight;
    }

    public void setAiInsight(String aiInsight) {
        this.aiInsight = aiInsight;
    }

    public List<String> getEvidenceSources() {
        return evidenceSources;
    }

    public void setEvidenceSources(List<String> evidenceSources) {
        this.evidenceSources = evidenceSources;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public void setStartedAt(Instant startedAt) {
        this.startedAt = startedAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public void setCompletedAt(Instant completedAt) {
        this.completedAt = completedAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }
}
