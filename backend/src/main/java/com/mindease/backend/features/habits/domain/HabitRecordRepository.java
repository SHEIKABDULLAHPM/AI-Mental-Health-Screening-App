package com.mindease.backend.features.habits.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface HabitRecordRepository extends MongoRepository<HabitRecord, String> {

    List<HabitRecord> findByUserIdAndHabitIdOrderByDateDesc(String userId, String habitId);

    Optional<HabitRecord> findByUserIdAndHabitIdAndDate(String userId, String habitId, LocalDate date);

    List<HabitRecord> findByUserIdAndDateBetweenOrderByDateAsc(String userId, LocalDate start, LocalDate end);

    long countByUserIdAndHabitIdAndCompletedTrue(String userId, String habitId);

    long countByUserIdAndHabitIdAndDateBetweenAndCompletedTrue(String userId, String habitId, LocalDate start, LocalDate end);
}
