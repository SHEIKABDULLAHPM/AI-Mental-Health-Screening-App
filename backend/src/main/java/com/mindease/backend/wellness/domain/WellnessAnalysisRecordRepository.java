package com.mindease.backend.wellness.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface WellnessAnalysisRecordRepository
        extends MongoRepository<WellnessAnalysisRecord, String> {

    /** The comparison baseline for the next analysis of the same type. */
    Optional<WellnessAnalysisRecord> findFirstByUserIdAndTypeOrderByAnalyzedAtDesc(
            String userId, String type);

    /** Stored analyses, newest first, for the in-app history list. */
    List<WellnessAnalysisRecord> findTop10ByUserIdOrderByAnalyzedAtDesc(String userId);

    List<WellnessAnalysisRecord> findTop10ByUserIdAndTypeOrderByAnalyzedAtDesc(
            String userId, String type);

    long countByUserId(String userId);
}
