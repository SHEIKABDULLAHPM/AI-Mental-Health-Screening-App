package com.mindease.backend.ai.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface AiAnalysisJobRepository extends MongoRepository<AiAnalysisJob, String> {

    Optional<AiAnalysisJob> findByIdAndUserId(String id, String userId);

    List<AiAnalysisJob> findByUserIdOrderByCreatedAtDesc(String userId);

    Optional<AiAnalysisJob> findByAssessmentId(String assessmentId);

    List<AiAnalysisJob> findByStatus(AiJobStatus status);

    List<AiAnalysisJob> findByStatusAndStartedAtBefore(AiJobStatus status, Instant before);

    List<AiAnalysisJob> findByStatusAndCreatedAtBefore(AiJobStatus status, Instant before);
}
