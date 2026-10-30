package com.mindease.backend.features.emotion.application;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.logging.AuditLog;
import com.mindease.backend.features.emotion.domain.EmotionEvent;
import com.mindease.backend.features.emotion.domain.EmotionClasses;
import com.mindease.backend.features.emotion.domain.EmotionEventRepository;
import com.mindease.backend.features.emotion.dto.CreateEmotionEventRequest;
import com.mindease.backend.features.emotion.dto.EmotionEventResponse;

/**
 * Emotion event ingestion. Enforces the vit-fer-7 event contract beyond
 * annotation validation: canonical score keys, score ranges, timestamp
 * sanity, and idempotent replay.
 */
@Service
public class EmotionEventService {

    /** Maximum acceptable clock skew / backfill window for capturedAt. */
    private static final Duration MAX_FUTURE_SKEW = Duration.ofMinutes(10);
    private static final Duration MAX_EVENT_AGE = Duration.ofDays(30);

    private final EmotionEventRepository repository;
    private final AuditLog audit;

    public EmotionEventService(EmotionEventRepository repository, AuditLog audit) {
        this.repository = repository;
        this.audit = audit;
    }

    /**
     * Idempotent create: a replayed idempotency key returns the original
     * event instead of persisting a duplicate.
     */
    public EmotionEventResponse recordEvent(String userId, CreateEmotionEventRequest request) {
        validateScores(request.scores());
        validateTimestamp(request.capturedAt());

        var existing = repository.findByUserIdAndIdempotencyKey(userId, request.idempotencyKey());
        if (existing.isPresent()) {
            return EmotionEventResponse.from(existing.get());
        }

        EmotionEvent event = new EmotionEvent();
        event.setUserId(userId);
        event.setEmotion(request.emotion());
        event.setScores(Map.copyOf(request.scores()));
        event.setCalibratedConfidence(request.calibratedConfidence());
        event.setFaceQuality(request.faceQuality());
        event.setModelId(request.modelId());
        event.setModelVersion(request.modelVersion());
        event.setPreprocessingVersion(request.preprocessingVersion());
        event.setStatus(request.status());
        event.setSource(request.source());
        event.setCapturedAt(request.capturedAt());
        event.setCreatedAt(Instant.now());
        event.setIdempotencyKey(request.idempotencyKey());

        EmotionEvent saved = repository.save(event);
        audit.event(userId, "emotion.recorded", saved.getId());
        return EmotionEventResponse.from(saved);
    }

    public List<EmotionEventResponse> listEvents(String userId, int page, int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), 100);
        var pageable = org.springframework.data.domain.PageRequest.of(safePage, safeSize);
        return repository.findByUserIdOrderByCapturedAtDesc(userId, pageable)
                .stream().map(EmotionEventResponse::from).toList();
    }

    public EmotionEventResponse getById(String userId, String id) {
        EmotionEvent event = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND, "Emotion event not found"));
        return EmotionEventResponse.from(event);
    }

    private void validateScores(Map<String, Double> scores) {
        if (!scores.keySet().equals(EmotionClasses.CANONICAL)) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "scores must contain exactly the 7 canonical classes");
        }
        for (var entry : scores.entrySet()) {
            Double v = entry.getValue();
            if (v == null || Double.isNaN(v) || v < 0.0 || v > 1.0) {
                throw new ApiException(ErrorCode.VALIDATION_FAILED,
                        "score out of range [0,1]: " + entry.getKey());
            }
        }
    }

    private void validateTimestamp(Instant capturedAt) {
        Instant now = Instant.now();
        if (capturedAt.isAfter(now.plus(MAX_FUTURE_SKEW))) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "capturedAt is too far in the future");
        }
        if (capturedAt.isBefore(now.minus(MAX_EVENT_AGE))) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "capturedAt is too old");
        }
    }
}
