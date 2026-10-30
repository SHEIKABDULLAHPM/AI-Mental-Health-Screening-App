package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface ExerciseSessionRepository extends MongoRepository<ExerciseSession, String> {

    Optional<ExerciseSession> findByUserIdAndDeviceIdAndStartTime(
            String userId, String deviceId, Instant startTime);

    /** Inclusive range: Spring Data's {@code Between} keyword is exclusive in MongoDB. */
    @Query(value = "{ 'userId': ?0, 'startTime': { $gte: ?1, $lte: ?2 } }",
            sort = "{ 'startTime': -1 }")
    List<ExerciseSession> findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
            String userId, Instant from, Instant to);

    Optional<ExerciseSession> findFirstByUserIdOrderByStartTimeDesc(String userId);

    long countByUserId(String userId);
}
