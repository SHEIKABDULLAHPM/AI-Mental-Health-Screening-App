package com.mindease.backend.ai.domain;

/**
 * Lifecycle of an AI analysis job. Jobs are created {@code QUEUED} on
 * assessment submission, claimed by the AI service for {@code PROCESSING} and
 * finish as {@code COMPLETED} or {@code FAILED}. A failed job may be retried
 * by its owner while attempts remain.
 */
public enum AiJobStatus {
    QUEUED,
    PROCESSING,
    COMPLETED,
    FAILED
}
