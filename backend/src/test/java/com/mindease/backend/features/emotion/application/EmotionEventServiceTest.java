package com.mindease.backend.features.emotion.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.logging.AuditLog;
import com.mindease.backend.features.emotion.domain.EmotionEvent;
import com.mindease.backend.features.emotion.domain.EmotionEventRepository;
import com.mindease.backend.features.emotion.dto.CreateEmotionEventRequest;
import com.mindease.backend.features.emotion.dto.EmotionEventResponse;

@ExtendWith(MockitoExtension.class)
class EmotionEventServiceTest {

    @Mock
    private EmotionEventRepository repository;

    @Mock
    private AuditLog audit;

    private EmotionEventService service;

    @BeforeEach
    void setUp() {
        service = new EmotionEventService(repository, audit);
    }

    private static Map<String, Double> validScores() {
        Map<String, Double> scores = new HashMap<>();
        scores.put("anger", 0.02);
        scores.put("disgust", 0.01);
        scores.put("fear", 0.03);
        scores.put("happy", 0.80);
        scores.put("neutral", 0.05);
        scores.put("sad", 0.03);
        scores.put("surprise", 0.06);
        return scores;
    }

    private static CreateEmotionEventRequest validRequest() {
        return new CreateEmotionEventRequest(
                "happy", validScores(), 0.84, 0.93,
                "vit-fer-7", "1.0.0", "2.0.0",
                "PREDICTED", "CAMERA", Instant.now(), "idem-key-1");
    }

    @Test
    void recordEvent_persistsWithServerIdentity_andAudits() {
        when(repository.findByUserIdAndIdempotencyKey("u1", "idem-key-1"))
                .thenReturn(Optional.empty());
        when(repository.save(any(EmotionEvent.class))).thenAnswer(inv -> {
            EmotionEvent e = inv.getArgument(0);
            e.setId("evt-1");
            return e;
        });

        EmotionEventResponse response = service.recordEvent("u1", validRequest());

        assertEquals("evt-1", response.id());
        assertEquals("happy", response.emotion());
        ArgumentCaptor<EmotionEvent> captor = ArgumentCaptor.forClass(EmotionEvent.class);
        verify(repository).save(captor.capture());
        assertEquals("u1", captor.getValue().getUserId());
        assertEquals("1.0.0", captor.getValue().getModelVersion());
        verify(audit).event("u1", "emotion.recorded", "evt-1");
    }

    @Test
    void recordEvent_replayReturnsOriginal_withoutDuplicate() {
        EmotionEvent original = new EmotionEvent();
        original.setId("evt-orig");
        original.setUserId("u1");
        original.setEmotion("neutral");
        when(repository.findByUserIdAndIdempotencyKey("u1", "idem-key-1"))
                .thenReturn(Optional.of(original));

        EmotionEventResponse response = service.recordEvent("u1", validRequest());

        assertEquals("evt-orig", response.id());
        verify(repository, never()).save(any());
    }

    @Test
    void recordEvent_rejectsNonCanonicalScoreKeys() {
        Map<String, Double> scores = validScores();
        scores.remove("fear");
        scores.put("contemptuous", 0.01);
        var request = new CreateEmotionEventRequest(
                "happy", scores, 0.8, 0.9,
                "vit-fer-7", "1.0.0", "2.0.0",
                "PREDICTED", "CAMERA", Instant.now(), "k2");

        ApiException ex = assertThrows(ApiException.class,
                () -> service.recordEvent("u1", request));
        assertEquals(ErrorCode.VALIDATION_FAILED, ex.getCode());
        verify(repository, never()).save(any());
    }

    @Test
    void recordEvent_rejectsOutOfRangeScore() {
        Map<String, Double> scores = validScores();
        scores.put("fear", 1.5);
        var request = new CreateEmotionEventRequest(
                "fear", scores, 0.8, 0.9,
                "vit-fer-7", "1.0.0", "2.0.0",
                "PREDICTED", "CAMERA", Instant.now(), "k3");

        assertThrows(ApiException.class, () -> service.recordEvent("u1", request));
        verify(repository, never()).save(any());
    }

    @Test
    void recordEvent_rejectsFutureTimestamp() {
        var request = new CreateEmotionEventRequest(
                "happy", validScores(), 0.8, 0.9,
                "vit-fer-7", "1.0.0", "2.0.0",
                "PREDICTED", "CAMERA", Instant.now().plusSeconds(3600), "k4");

        assertThrows(ApiException.class, () -> service.recordEvent("u1", request));
        verify(repository, never()).save(any());
    }

    @Test
    void recordEvent_rejectsAncientTimestamp() {
        var request = new CreateEmotionEventRequest(
                "happy", validScores(), 0.8, 0.9,
                "vit-fer-7", "1.0.0", "2.0.0",
                "PREDICTED", "CAMERA", Instant.now().minusSeconds(31L * 86400), "k5");

        assertThrows(ApiException.class, () -> service.recordEvent("u1", request));
        verify(repository, never()).save(any());
    }

    @Test
    void recordEvent_acceptsUnknownEmotion_forUncertainFrames() {
        when(repository.findByUserIdAndIdempotencyKey("u9", "k6"))
                .thenReturn(Optional.empty());
        when(repository.save(any(EmotionEvent.class))).thenAnswer(inv -> inv.getArgument(0));
        var request = new CreateEmotionEventRequest(
                "unknown", validScores(), 0.2, 0.4,
                "vit-fer-7", "1.0.0", "2.0.0",
                "UNCERTAIN", "CAMERA", Instant.now(), "k6");

        EmotionEventResponse response = service.recordEvent("u9", request);
        assertEquals("unknown", response.emotion());
        assertEquals("UNCERTAIN", response.status());
    }

    @Test
    void getById_enforcesUserIsolation() {
        when(repository.findByIdAndUserId("evt-x", "u2")).thenReturn(Optional.empty());

        ApiException ex = assertThrows(ApiException.class, () -> service.getById("u2", "evt-x"));
        assertEquals(ErrorCode.NOT_FOUND, ex.getCode());
    }

    @Test
    void getById_returnsOwnEvent() {
        EmotionEvent event = new EmotionEvent();
        event.setId("evt-own");
        event.setUserId("u2");
        event.setEmotion("sad");
        when(repository.findByIdAndUserId("evt-own", "u2")).thenReturn(Optional.of(event));

        assertEquals("sad", service.getById("u2", "evt-own").emotion());
    }

    @Test
    void listEvents_clampsPageSize() {
        when(repository.findByUserIdOrderByCapturedAtDesc(any(), any()))
                .thenReturn(java.util.List.of());
        var result = service.listEvents("u1", -1, 5000);
        assertTrue(result.isEmpty());
        ArgumentCaptor<org.springframework.data.domain.Pageable> captor =
                ArgumentCaptor.forClass(org.springframework.data.domain.Pageable.class);
        verify(repository).findByUserIdOrderByCapturedAtDesc(any(), captor.capture());
        assertEquals(100, captor.getValue().getPageSize());
    }
}
