package com.mindease.backend.ai.dto;

import java.time.Instant;

import com.mindease.backend.ai.domain.AiAnalysisJob;
import com.mindease.backend.ai.domain.AiJobStatus;

/**
 * Status projection returned to the caller for GET /ai-analysis/{jobId}/status.
 */
public record AiAnalysisJobDto(
        String jobId,
        AiJobStatus status,
        int attemptCount,
        int maxAttempts,
        String errorMessage,
        Instant createdAt,
        Instant updatedAt) {

    public static AiAnalysisJobDto from(AiAnalysisJob job) {
        return new AiAnalysisJobDto(
                job.getId(),
                job.getStatus(),
                job.getAttemptCount(),
                job.getMaxAttempts(),
                job.getErrorMessage(),
                job.getCreatedAt(),
                job.getUpdatedAt());
    }
}
