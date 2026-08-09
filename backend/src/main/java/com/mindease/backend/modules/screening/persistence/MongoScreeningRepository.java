package com.mindease.backend.modules.screening.persistence;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

import com.mindease.backend.modules.screening.domain.Screening;

/**
 * Spring Data MongoDB adapter for {@link com.mindease.backend.modules.screening.domain.Screening}.
 */
public interface MongoScreeningRepository extends MongoRepository<Screening, String> {

    List<Screening> findByUserId(String userId);

    default Optional<Screening> byId(String id) {
        return findById(id);
    }
}