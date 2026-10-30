package com.mindease.backend.features.physical.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface SyncSessionRepository extends MongoRepository<SyncSession, String> {

    Optional<SyncSession> findFirstByUserIdAndStatusOrderByStartedAtDesc(String userId, SyncStatus status);

    Optional<SyncSession> findFirstByUserIdOrderByStartedAtDesc(String userId);

    /** Batch idempotency lookup: recognises a replayed ingestion attempt. */
    Optional<SyncSession> findFirstByUserIdAndClientSyncId(String userId, String clientSyncId);

    List<SyncSession> findTop20ByUserIdOrderByStartedAtDesc(String userId);
}
