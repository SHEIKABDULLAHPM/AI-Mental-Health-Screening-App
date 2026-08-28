package com.mindease.backend.features.journal.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface JournalEntryRepository extends MongoRepository<JournalEntry, String> {

    List<JournalEntry> findByUserIdOrderByCreatedAtDesc(String userId, Pageable pageable);

    Optional<JournalEntry> findByIdAndUserId(String id, String userId);

    List<JournalEntry> findByUserIdAndTypeOrderByCreatedAtDesc(String userId, String type, Pageable pageable);

    @Query("{'userId': ?0, $or: [{'title': {$regex: ?1, $options: 'i'}}, {'content': {$regex: ?1, $options: 'i'}}]}")
    List<JournalEntry> searchByUserIdAndText(String userId, String query, Pageable pageable);

    long countByUserId(String userId);

    long countByUserIdAndType(String userId, String type);
}
