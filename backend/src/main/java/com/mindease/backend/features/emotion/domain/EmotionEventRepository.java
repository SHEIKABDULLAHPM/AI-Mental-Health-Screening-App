package com.mindease.backend.features.emotion.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface EmotionEventRepository extends MongoRepository<EmotionEvent, String> {

    Optional<EmotionEvent> findByIdAndUserId(String id, String userId);

    Optional<EmotionEvent> findByUserIdAndIdempotencyKey(String userId, String idempotencyKey);

    List<EmotionEvent> findByUserIdOrderByCapturedAtDesc(String userId, Pageable pageable);

    List<EmotionEvent> findByUserIdAndCapturedAtAfterOrderByCapturedAtDesc(
            String userId, Instant capturedAt, Pageable pageable);
}
