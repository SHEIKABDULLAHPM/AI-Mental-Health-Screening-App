package com.mindease.backend.ai.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.ai.application.AiAnalysisJobService;
import com.mindease.backend.ai.dto.AiAnalysisJobDto;
import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;

/**
 * User-facing AI analysis endpoints. All job ids are ownership-scoped to the
 * authenticated caller.
 */
@RestController
@RequestMapping("/api/v1/ai-analysis")
public class AiAnalysisController {

    private final AiAnalysisJobService service;

    public AiAnalysisController(AiAnalysisJobService service) {
        this.service = service;
    }

    @GetMapping("/{jobId}/status")
    public ResponseEntity<ApiResponse<AiAnalysisJobDto>> status(@PathVariable String jobId) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.statusFor(userId, jobId)));
    }

    @PostMapping("/{jobId}/retry")
    public ResponseEntity<ApiResponse<AiAnalysisJobDto>> retry(@PathVariable String jobId) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.retry(userId, jobId)));
    }
}
