package com.mindease.backend.features.habits.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface HabitRepository extends MongoRepository<Habit, String> {

    List<Habit> findByUserIdAndActiveTrueOrderByCreatedAtDesc(String userId);

    Optional<Habit> findByIdAndUserId(String id, String userId);

    long countByUserIdAndActiveTrue(String userId);
}
