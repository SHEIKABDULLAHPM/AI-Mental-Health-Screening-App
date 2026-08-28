package com.mindease.backend.personalization.domain;

import java.time.Instant;
import java.util.List;

import org.springframework.data.mongodb.repository.MongoRepository;

/**
 * Repository for cross-feature personalization feedback events.
 */
public interface PersonalizationFeedbackRepository extends MongoRepository<PersonalizationFeedback, String> {

    List<PersonalizationFeedback> findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
            String userId, Instant after);

    List<PersonalizationFeedback> findByUserIdAndEventTypeAndCreatedAtAfterOrderByCreatedAtDesc(
            String userId, String eventType, Instant after);

    List<PersonalizationFeedback> findByUserIdAndContentIdOrderByCreatedAtDesc(
            String userId, String contentId);

    long countByUserIdAndEventTypeAndCreatedAtAfter(
            String userId, String eventType, Instant after);
}
