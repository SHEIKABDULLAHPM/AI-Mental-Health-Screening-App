package com.mindease.backend.features.challenges.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface ChallengeRepository extends MongoRepository<Challenge, String> {

    List<Challenge> findByActiveTrue();

    Optional<Challenge> findByIdAndActiveTrue(String id);
}
