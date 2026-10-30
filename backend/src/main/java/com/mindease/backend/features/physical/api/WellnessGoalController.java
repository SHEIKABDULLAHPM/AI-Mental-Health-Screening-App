package com.mindease.backend.features.physical.api;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.physical.application.WellnessGoalService;
import com.mindease.backend.features.physical.dto.WellnessGoalDtos;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

/** Goal configuration and progress computed from real records. */
@RestController
@RequestMapping("/api/v1/physical/goals")
public class WellnessGoalController {

    private final WellnessGoalService goals;

    public WellnessGoalController(WellnessGoalService goals) {
        this.goals = goals;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<WellnessGoalDtos.GoalsResponse>> overview() {
        return ResponseEntity.ok(ApiResponse.ok(goals.overview(AuthenticatedUser.currentId())));
    }

    @PutMapping
    public ResponseEntity<ApiResponse<WellnessGoalDtos.GoalsResponse>> update(
            @Valid @RequestBody WellnessGoalDtos.GoalRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(
                goals.update(AuthenticatedUser.currentId(), request)));
    }

    /**
     * Applies AI-suggested targets. Suggestions never overwrite a target the
     * user set, and every skipped suggestion is reported back.
     */
    @PostMapping("/ai-recommendations")
    public ResponseEntity<ApiResponse<WellnessGoalDtos.ApplyRecommendationsResponse>>
            applyAiRecommendations(
                    @RequestBody WellnessGoalDtos.ApplyRecommendationsRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(goals.applyAiRecommendations(
                AuthenticatedUser.currentId(),
                request == null ? List.of() : request.recommendations())));
    }
}
