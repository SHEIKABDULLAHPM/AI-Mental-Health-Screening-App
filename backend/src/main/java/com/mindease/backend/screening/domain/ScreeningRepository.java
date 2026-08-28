package com.mindease.backend.screening.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface ScreeningRepository extends MongoRepository<Screening, String> {

    Optional<Screening> findFirstByUserIdAndStatus(String userId, ScreeningStatus status);

    List<Screening> findByUserIdOrderByUpdatedAtDesc(String userId);

    List<Screening> findByTenantIdAndUserId(String tenantId, String userId);

    List<Screening> findByTenantId(String tenantId);
}