package com.mindease.backend.features.challenges.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface UserChallengeRepository extends MongoRepository<UserChallenge, String> {

    List<UserChallenge> findByUserIdOrderByStartedAtDesc(String userId);

    Optional<UserChallenge> findByIdAndUserId(String id, String userId);

    /**
     * Locate the user's progress on a challenge for a specific period.
     */
    Optional<UserChallenge> findByUserIdAndChallengeIdAndPeriodStart(
            String userId, String challengeId, String periodStart);

    /**
     * Latest (any period) progress for a challenge. Used to detect an in-flight
     * instance when the exact period is not yet known (e.g. during start).
     */
    Optional<UserChallenge> findTopByUserIdAndChallengeIdOrderByCreatedAtDesc(
            String userId, String challengeId);

    List<UserChallenge> findByUserIdAndStatusOrderByUpdatedAtDesc(String userId, String status);

    List<UserChallenge> findByUserIdAndStatusInOrderByUpdatedAtDesc(
            String userId, List<String> statuses);

    boolean existsByUserIdAndChallengeIdAndPeriodStart(String userId, String challengeId, String periodStart);
}
