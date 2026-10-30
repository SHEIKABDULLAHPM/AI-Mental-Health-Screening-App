package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface HydrationEntryRepository extends MongoRepository<HydrationEntry, String> {

    List<HydrationEntry> findByUserIdAndDateOrderByTimestampAsc(String userId, LocalDate date);

    /**
     * Inclusive range covering both boundary days.
     *
     * <p>Spring Data MongoDB translates the derived {@code Between} keyword to
     * {@code $gt} / {@code $lt}, so an entry logged today was invisible in
     * today's total. The explicit query is required for a correct daily
     * roll-up.</p>
     */
    @Query(value = "{ 'userId': ?0, 'date': { $gte: ?1, $lte: ?2 } }",
            sort = "{ 'date': -1 }")
    List<HydrationEntry> findByUserIdAndDateBetweenOrderByDateDesc(String userId,
                                                                   LocalDate from, LocalDate to);

    Optional<HydrationEntry> findByIdAndUserId(String id, String userId);

    void deleteByIdAndUserId(String id, String userId);

    long countByUserId(String userId);
}
