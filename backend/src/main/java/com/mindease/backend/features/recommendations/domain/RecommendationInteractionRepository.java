package com.mindease.backend.features.recommendations.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface RecommendationInteractionRepository extends MongoRepository<RecommendationInteraction, String> {

    /** Check for idempotent requests */
    Optional<RecommendationInteraction> findByUserIdAndRequestId(String userId, String requestId);

    /** Recent interactions for a user */
    List<RecommendationInteraction> findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
            String userId, Instant after);

    /** Check if user interacted with specific content */
    List<RecommendationInteraction> findByUserIdAndContentIdAndInteractionType(
            String userId, String contentId, String interactionType);

    /** Get recent interactions for cooldown detection */
    List<RecommendationInteraction> findByUserIdAndContentIdInAndInteractionTypeIn(
            String userId, List<String> contentIds, List<String> interactionTypes);

    /** Count interactions of a type for a user within a time window */
    long countByUserIdAndContentIdAndInteractionTypeAndCreatedAtAfter(
            String userId, String contentId, String interactionType, Instant after);
}
