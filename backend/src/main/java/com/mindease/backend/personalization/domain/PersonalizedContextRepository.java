package com.mindease.backend.personalization.domain;

import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

/**
 * Repository for the centralized personalized context document.
 * One document per user — upserted on each refresh.
 */
public interface PersonalizedContextRepository extends MongoRepository<PersonalizedContext, String> {

    Optional<PersonalizedContext> findFirstByUserIdOrderByGeneratedAtDesc(String userId);

    Optional<PersonalizedContext> findFirstByUserIdAndExpiresAtAfterOrderByGeneratedAtDesc(
            String userId, java.time.Instant after);

    void deleteByUserId(String userId);
}
