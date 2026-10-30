package com.mindease.backend.wellness.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.wellness.application.MentalWellnessAnalysisService;
import com.mindease.backend.wellness.dto.MentalWellnessAnalysisDto;

@RestController
@RequestMapping("/api/v1")
public class MentalWellnessAnalyzeController {

    private final MentalWellnessAnalysisService service;

    public MentalWellnessAnalyzeController(MentalWellnessAnalysisService service) {
        this.service = service;
    }

    @PostMapping("/mental-wellness/analyze")
    public ResponseEntity<ApiResponse<MentalWellnessAnalysisDto>> analyze() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }

    @GetMapping("/mental-wellness/analyze")
    public ResponseEntity<ApiResponse<MentalWellnessAnalysisDto>> analyzeGet() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.analyze(userId)));
    }
}
