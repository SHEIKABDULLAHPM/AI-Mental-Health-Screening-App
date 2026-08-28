package com.mindease.backend.features.mood.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface MoodEntryRepository extends MongoRepository<MoodEntry, String> {

    List<MoodEntry> findByUserIdOrderByRecordedAtDesc(String userId, Pageable pageable);

    /** Date-bounded query for trends — avoids loading the entire collection. */
    List<MoodEntry> findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
            String userId, Instant recordedAfter);

    Optional<MoodEntry> findByIdAndUserId(String id, String userId);

    long countByUserId(String userId);

    /** All entries for streak calculation — fetches only recordedAt dates. */
    List<MoodEntry> findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
            String userId, Instant recordedAfter, Pageable pageable);
}
