package com.mindease.backend.features.checkin.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface DailyCheckinRepository extends MongoRepository<DailyCheckin, String> {

    Optional<DailyCheckin> findByUserIdAndDate(String userId, LocalDate date);

    List<DailyCheckin> findByUserIdOrderByDateDesc(String userId, Pageable pageable);

    /**
     * Inclusive range: Spring Data's {@code Between} keyword derives
     * {@code $gt}/{@code $lt} (exclusive) in MongoDB, which made today's
     * check-in invisible to same-day consumers (Mind–Body insights) and broke
     * the documented coverage counts. Declared explicitly so the boundary
     * days are always included; guarded by {@code RepositoryRangeQueryContractTest}.
     */
    @Query(value = "{ 'userId': ?0, 'date': { $gte: ?1, $lte: ?2 } }",
            sort = "{ 'date': 1 }")
    List<DailyCheckin> findByUserIdAndDateBetweenOrderByDateAsc(
            String userId, LocalDate from, LocalDate to);

    long countByUserId(String userId);
}
