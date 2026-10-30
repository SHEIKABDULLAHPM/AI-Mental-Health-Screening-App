package com.mindease.backend.features.physical.domain;

import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface WellnessGoalRepository extends MongoRepository<WellnessGoal, String> {

    Optional<WellnessGoal> findByUserId(String userId);
}
