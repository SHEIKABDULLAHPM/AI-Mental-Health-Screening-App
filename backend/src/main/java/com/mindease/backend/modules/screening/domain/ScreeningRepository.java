package com.mindease.backend.modules.screening.domain;

import java.util.Optional;

/**
 * Domain repository contract - decouples application from persistence.
 */
public interface ScreeningRepository {

    Screening save(Screening screening);

    Optional<Screening> findById(String id);

    java.util.List<Screening> findByUserId(String userId);
}