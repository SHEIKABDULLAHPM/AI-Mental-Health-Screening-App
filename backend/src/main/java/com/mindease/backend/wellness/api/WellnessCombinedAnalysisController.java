package com.mindease.backend.wellness.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.wellness.application.CombinedWellnessAnalysisService;
import com.mindease.backend.wellness.dto.CombinedWellnessAnalysisDto;

@RestController
@RequestMapping("/api/v1")
public class WellnessCombinedAnalysisController {

    private final CombinedWellnessAnalysisService service;

    public WellnessCombinedAnalysisController(CombinedWellnessAnalysisService service) {
        this.service = service;
    }

    @PostMapping("/wellness/combined-analyze")
    public ResponseEntity<ApiResponse<CombinedWellnessAnalysisDto>> combinedAnalyze() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }

    @GetMapping("/wellness/combined-analyze")
    public ResponseEntity<ApiResponse<CombinedWellnessAnalysisDto>> combinedAnalyzeGet() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }

    @PostMapping("/wellness/combined/analyze-now")
    public ResponseEntity<ApiResponse<CombinedWellnessAnalysisDto>> analyzeNow() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }
}
