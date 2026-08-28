package com.mindease.backend.features.recommendations.api;

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
import com.mindease.backend.features.recommendations.application.RecommendationService;
import com.mindease.backend.features.recommendations.dto.FeedbackRequest;
import com.mindease.backend.features.recommendations.dto.InteractionRequest;
import com.mindease.backend.features.recommendations.dto.RecommendationResponse;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/recommendations")
public class RecommendationController {

    private final RecommendationService service;

    public RecommendationController(RecommendationService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<RecommendationResponse>>> list(
            @RequestParam(required = false) String category) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getRecommendations(userId, category)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<RecommendationResponse>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getRecommendationById(userId, id)));
    }

    @PostMapping("/{id}/feedback")
    public ResponseEntity<ApiResponse<Void>> recordFeedback(
            @PathVariable String id,
            @Valid @RequestBody FeedbackRequest request) {
        String userId = AuthenticatedUser.currentId();
        service.recordFeedback(userId, id, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.ok());
    }

    @PostMapping("/{id}/interaction")
    public ResponseEntity<ApiResponse<Void>> recordInteraction(
            @PathVariable String id,
            @Valid @RequestBody InteractionRequest request) {
        String userId = AuthenticatedUser.currentId();
        service.recordInteraction(userId, id, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.ok());
    }
}
