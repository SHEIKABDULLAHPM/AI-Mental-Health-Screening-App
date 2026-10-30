package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface HealthReadingRepository extends MongoRepository<HealthReading, String> {

    Optional<HealthReading> findByUserIdAndDeviceIdAndMetricTypeAndTimestamp(
            String userId, String deviceId, HealthMetricType metricType, Instant timestamp);

    /** Inclusive range: Spring Data's {@code Between} keyword is exclusive in MongoDB. */
    @Query(value = "{ 'userId': ?0, 'metricType': ?1, 'timestamp': { $gte: ?2, $lte: ?3 } }",
            sort = "{ 'timestamp': -1 }")
    List<HealthReading> findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
            String userId, HealthMetricType metricType, Instant from, Instant to);

    List<HealthReading> findByUserIdAndDateAndMetricTypeOrderByTimestampAsc(
            String userId, LocalDate date, HealthMetricType metricType);

    Optional<HealthReading> findFirstByUserIdAndMetricTypeOrderByTimestampDesc(
            String userId, HealthMetricType metricType);

    Optional<HealthReading> findFirstByUserIdAndDeviceIdAndMetricTypeOrderByTimestampDesc(
            String userId, String deviceId, HealthMetricType metricType);

    long countByUserId(String userId);
}
