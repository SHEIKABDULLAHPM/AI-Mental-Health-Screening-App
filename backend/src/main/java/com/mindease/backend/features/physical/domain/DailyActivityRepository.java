package com.mindease.backend.features.physical.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface DailyActivityRepository extends MongoRepository<DailyActivity, String> {

    Optional<DailyActivity> findByUserIdAndDate(String userId, LocalDate date);

    /** Inclusive range: Spring Data's {@code Between} keyword is exclusive in MongoDB. */
    @Query(value = "{ 'userId': ?0, 'date': { $gte: ?1, $lte: ?2 } }",
            sort = "{ 'date': -1 }")
    List<DailyActivity> findByUserIdAndDateBetweenOrderByDateDesc(
            String userId, LocalDate from, LocalDate to);

    List<DailyActivity> findTop14ByUserIdOrderByDateDesc(String userId);

    void deleteByIdAndUserId(String id, String userId);
}
