package com.mindease.backend.features.emotion.api;

import java.time.Duration;
import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.emotion.application.EmotionEventService;
import com.mindease.backend.features.emotion.dto.CreateEmotionEventRequest;
import com.mindease.backend.features.emotion.dto.EmotionEventResponse;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.security.RateLimiterService;

import jakarta.validation.Valid;

/**
 * Facial-expression event ingestion (vit-fer-7 structured output).
 * Identity always comes from the JWT; rate-limited per user.
 */
@RestController
@RequestMapping("/api/v1/emotions")
public class EmotionEventController {

    private static final int RATE_LIMIT = 60;
    private static final Duration RATE_WINDOW = Duration.ofMinutes(1);

    private final EmotionEventService service;
    private final RateLimiterService rateLimiter;

    public EmotionEventController(EmotionEventService service, RateLimiterService rateLimiter) {
        this.service = service;
        this.rateLimiter = rateLimiter;
    }

    @PostMapping("/events")
    public ResponseEntity<ApiResponse<EmotionEventResponse>> record(
            @Valid @RequestBody CreateEmotionEventRequest request) {
        String userId = AuthenticatedUser.currentId();
        if (!rateLimiter.allow("emotion:" + userId, RATE_LIMIT, RATE_WINDOW)) {
            throw new ApiException(ErrorCode.RATE_LIMITED, "Too many emotion events");
        }
        EmotionEventResponse response = service.recordEvent(userId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @GetMapping("/events")
    public ResponseEntity<ApiResponse<List<EmotionEventResponse>>> list(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.listEvents(userId, page, size)));
    }

    @GetMapping("/events/{id}")
    public ResponseEntity<ApiResponse<EmotionEventResponse>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getById(userId, id)));
    }
}
