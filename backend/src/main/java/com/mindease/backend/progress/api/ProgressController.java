package com.mindease.backend.progress.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.progress.application.ProgressService;
import com.mindease.backend.progress.dto.ProgressDto;
import com.mindease.backend.security.AuthenticatedUser;

/**
 * REST API for the Progress feature.
 * Returns aggregated, real-time progress data computed from actual user activity.
 */
@RestController
@RequestMapping("/api/v1/progress")
public class ProgressController {

    private final ProgressService service;

    public ProgressController(ProgressService service) {
        this.service = service;
    }

    /**
     * Get the complete progress summary for the authenticated user.
     * All data is computed from real MongoDB collections — no static values.
     */
    @GetMapping
    public ResponseEntity<ApiResponse<ProgressDto>> getProgress() {
        String userId = AuthenticatedUser.currentId();
        ProgressDto progress = service.getProgress(userId);
        return ResponseEntity.ok(ApiResponse.ok(progress));
    }
}
