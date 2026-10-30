package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface BodyMeasurementRepository extends MongoRepository<BodyMeasurement, String> {

    List<BodyMeasurement> findByUserIdOrderByMeasuredAtDesc(String userId, Pageable pageable);

    /**
     * Inclusive range.
     *
     * <p>Spring Data MongoDB maps the {@code Between} keyword to {@code $gt} /
     * {@code $lt} (exclusive), which silently drops measurements taken exactly
     * on the window boundaries. The explicit query below keeps the bounds
     * inclusive, matching the JPA semantics callers expect.</p>
     */
    @Query(value = "{ 'userId': ?0, 'measuredAt': { $gte: ?1, $lte: ?2 } }",
            sort = "{ 'measuredAt': -1 }")
    List<BodyMeasurement> findByUserIdAndMeasuredAtBetweenOrderByMeasuredAtDesc(
            String userId, Instant from, Instant to);

    Optional<BodyMeasurement> findFirstByUserIdAndWeightKgNotNullOrderByMeasuredAtDesc(String userId);

    Optional<BodyMeasurement> findFirstByUserIdAndHeightCmNotNullOrderByMeasuredAtDesc(String userId);

    Optional<BodyMeasurement> findByIdAndUserId(String id, String userId);

    void deleteByIdAndUserId(String id, String userId);
}
