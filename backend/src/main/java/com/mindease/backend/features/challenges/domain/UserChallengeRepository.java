package com.mindease.backend.features.challenges.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface UserChallengeRepository extends MongoRepository<UserChallenge, String> {

    List<UserChallenge> findByUserIdOrderByStartedAtDesc(String userId);

    Optional<UserChallenge> findByUserIdAndChallengeId(String userId, String challengeId);

    Optional<UserChallenge> findByIdAndUserId(String id, String userId);

    List<UserChallenge> findByUserIdAndCompletedFalseOrderByStartedAtDesc(String userId);

    List<UserChallenge> findByUserIdAndCompletedTrueOrderByCompletedAtDesc(String userId);
}
