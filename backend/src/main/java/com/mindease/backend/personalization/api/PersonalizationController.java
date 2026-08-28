package com.mindease.backend.personalization.api;

import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.personalization.domain.PersonalizationFeedback;
import com.mindease.backend.personalization.dto.PersonalizedContextResponse;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

/**
 * REST API for the centralized personalization engine.
 *
 * <p>All endpoints require JWT authentication. User identity is always
 * derived from the security context — never from the request body.</p>
 */
@RestController
@RequestMapping("/api/v1/personalization")
public class PersonalizationController {

    private final PersonalizationService service;

    public PersonalizationController(PersonalizationService service) {
        this.service = service;
    }

    /**
     * Get the current personalized context for the authenticated user.
     * Returns cached context if fresh; rebuilds if stale.
     */
    @GetMapping("/context")
    public ResponseEntity<ApiResponse<PersonalizedContextResponse>> getContext() {
        String userId = AuthenticatedUser.currentId();
        var context = service.getContext(userId);
        return ResponseEntity.ok(ApiResponse.ok(PersonalizedContextResponse.from(context)));
    }

    /**
     * Force a context refresh. Called when a significant feature event occurs.
     */
    @PostMapping("/context/refresh")
    public ResponseEntity<ApiResponse<PersonalizedContextResponse>> refreshContext() {
        String userId = AuthenticatedUser.currentId();
        var context = service.refreshContext(userId);
        return ResponseEntity.ok(ApiResponse.ok(PersonalizedContextResponse.from(context)));
    }

    /**
     * Record a cross-feature feedback event.
     */
    @PostMapping("/feedback")
    public ResponseEntity<ApiResponse<Void>> recordFeedback(
            @Valid @RequestBody FeedbackRequest request) {
        String userId = AuthenticatedUser.currentId();
        service.recordFeedback(userId, request.eventType(), request.contentId(),
                request.sourceFeature(), request.metadata());
        return ResponseEntity.ok(ApiResponse.ok());
    }

    /**
     * Get recent feedback events for the authenticated user.
     */
    @GetMapping("/feedback")
    public ResponseEntity<ApiResponse<List<PersonalizationFeedback>>> getRecentFeedback() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getRecentFeedback(userId)));
    }

    /**
     * Feedback request DTO.
     */
    public record FeedbackRequest(
            @NotBlank String eventType,
            String contentId,
            String sourceFeature,
            Map<String, String> metadata
    ) {}
}
