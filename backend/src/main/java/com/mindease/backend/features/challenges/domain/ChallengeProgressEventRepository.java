package com.mindease.backend.features.challenges.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface ChallengeProgressEventRepository
        extends MongoRepository<ChallengeProgressEvent, String> {

    /** Whether a specific source record already contributed to a challenge period. */
    boolean existsByUserIdAndChallengeIdAndPeriodStartAndSourceRecordId(
            String userId, String challengeId, String periodStart, String sourceRecordId);

    Optional<ChallengeProgressEvent> findByUserIdAndChallengeIdAndPeriodStartAndSourceRecordId(
            String userId, String challengeId, String periodStart, String sourceRecordId);

    List<ChallengeProgressEvent> findByUserIdAndActivityKindOrderByOccurredAtDesc(
            String userId, String activityKind);

    List<ChallengeProgressEvent> findByUserIdOrderByOccurredAtDesc(String userId);
}
