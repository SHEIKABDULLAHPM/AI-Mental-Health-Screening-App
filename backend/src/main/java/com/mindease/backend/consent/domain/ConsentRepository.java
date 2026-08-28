package com.mindease.backend.consent.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface ConsentRepository extends MongoRepository<ConsentRecord, String> {

    List<ConsentRecord> findByUserId(String userId);

    Optional<ConsentRecord> findByUserIdAndConsentType(String userId, ConsentType type);

    List<ConsentRecord> findByTenantIdAndUserId(String tenantId, String userId);

    List<ConsentRecord> findByTenantId(String tenantId);
}