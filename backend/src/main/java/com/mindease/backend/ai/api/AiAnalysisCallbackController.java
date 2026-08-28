package com.mindease.backend.ai.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.ai.application.AiAnalysisJobService;
import com.mindease.backend.ai.domain.AiAnalysisJob;
import com.mindease.backend.ai.domain.DeterministicScores;
import com.mindease.backend.ai.dto.AiAnalysisFailRequest;
import com.mindease.backend.ai.dto.AiAnalysisResultRequest;
import com.mindease.backend.common.api.ApiResponse;

/**
 * Internal AI-service callbacks. Protected by the shared internal API key
 * (header {@code X-Internal-Api-Key}) enforced by the security filter, and
 * ownership is never taken from the client - jobs are located by id.
 */
@RestController
@RequestMapping("/api/v1/internal/ai-analysis")
public class AiAnalysisCallbackController {

    private final AiAnalysisJobService service;

    public AiAnalysisCallbackController(AiAnalysisJobService service) {
        this.service = service;
    }

    /** Claims the job and returns the deterministic (minimal) input for the LLM. */
    @PostMapping("/{jobId}/claim")
    public ResponseEntity<ApiResponse<DeterministicScores>> claim(@PathVariable String jobId) {
        return ResponseEntity.ok(ApiResponse.ok(service.claim(jobId)));
    }

    /** Posts the completed AI result. */
    @PostMapping("/{jobId}/complete")
    public ResponseEntity<ApiResponse<AiAnalysisJob>> complete(
            @PathVariable String jobId, @RequestBody AiAnalysisResultRequest result) {
        return ResponseEntity.ok(ApiResponse.ok(service.complete(jobId, result)));
    }

    /** Reports a processing failure. */
    @PostMapping("/{jobId}/fail")
    public ResponseEntity<ApiResponse<AiAnalysisJob>> fail(
            @PathVariable String jobId, @RequestBody(required = false) AiAnalysisFailRequest body) {
        return ResponseEntity.ok(ApiResponse.ok(
                service.fail(jobId, body == null ? null : body.error())));
    }
}
