package com.mindease.backend.features.physical.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.physical.application.PhysicalWellnessAnalysisService;
import com.mindease.backend.features.physical.dto.PhysicalWellnessAnalysisDto;
import com.mindease.backend.security.AuthenticatedUser;

@RestController
@RequestMapping("/api/v1/physical")
public class PhysicalAnalysisController {

    private final PhysicalWellnessAnalysisService service;

    public PhysicalAnalysisController(PhysicalWellnessAnalysisService service) {
        this.service = service;
    }

    @GetMapping("/analysis")
    public ResponseEntity<ApiResponse<PhysicalWellnessAnalysisDto>> analysisGet() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }

    @PostMapping("/analysis")
    public ResponseEntity<ApiResponse<PhysicalWellnessAnalysisDto>> analysisPost() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }

    @GetMapping("/analyze")
    public ResponseEntity<ApiResponse<PhysicalWellnessAnalysisDto>> analyzeGet() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }

    @PostMapping("/analyze")
    public ResponseEntity<ApiResponse<PhysicalWellnessAnalysisDto>> analyze() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }
}
