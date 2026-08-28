package com.mindease.backend.features.relax.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface UserRelaxCompletionRepository extends MongoRepository<UserRelaxCompletion, String> {

    List<UserRelaxCompletion> findByUserIdAndActivityIdOrderByCompletedAtDesc(String userId, String activityId);

    Optional<UserRelaxCompletion> findByUserIdAndActivityIdAndCompletedAtBetween(
            String userId, String activityId, Instant start, Instant end);
}
