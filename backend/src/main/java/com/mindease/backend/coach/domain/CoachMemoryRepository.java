package com.mindease.backend.coach.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface CoachMemoryRepository extends MongoRepository<CoachMemory, String> {

    List<CoachMemory> findByUserIdAndCategoryOrderByConfidenceDesc(
            String userId, String category);

    List<CoachMemory> findByUserIdOrderByConfidenceDesc(String userId);

    Optional<CoachMemory> findByIdAndUserId(String id, String userId);

    List<CoachMemory> findByUserIdAndExpiresAtOrExpiresAtIsNullOrderByConfidenceDesc(
            String userId, Instant notExpired);

    void deleteByUserId(String userId);
}
