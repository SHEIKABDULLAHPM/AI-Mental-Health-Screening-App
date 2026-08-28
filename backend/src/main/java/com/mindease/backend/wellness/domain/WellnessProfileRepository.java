package com.mindease.backend.wellness.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface WellnessProfileRepository extends MongoRepository<WellnessProfile, String> {

    Optional<WellnessProfile> findFirstByUserIdOrderByCreatedAtDesc(String userId);

    Optional<WellnessProfile> findByUserIdAndAssessmentId(String userId, String assessmentId);

    List<WellnessProfile> findByAssessmentId(String assessmentId);

    List<WellnessProfile> findByTenantIdAndUserId(String tenantId, String userId);

    List<WellnessProfile> findByTenantId(String tenantId);
}