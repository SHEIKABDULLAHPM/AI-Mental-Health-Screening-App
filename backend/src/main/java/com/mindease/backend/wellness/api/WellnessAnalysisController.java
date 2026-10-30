package com.mindease.backend.wellness.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.wellness.application.CombinedWellnessAnalysisService;
import com.mindease.backend.wellness.application.MentalWellnessAnalysisService;
import com.mindease.backend.wellness.dto.CombinedWellnessAnalysisDto;
import com.mindease.backend.wellness.dto.MentalWellnessAnalysisDto;

@RestController
@RequestMapping("/api/v1/wellness")
public class WellnessAnalysisController {

    private final MentalWellnessAnalysisService mentalService;
    private final CombinedWellnessAnalysisService combinedService;

    public WellnessAnalysisController(MentalWellnessAnalysisService mentalService,
                                     CombinedWellnessAnalysisService combinedService) {
        this.mentalService = mentalService;
        this.combinedService = combinedService;
    }

    @GetMapping("/mental/analyze")
    public ResponseEntity<ApiResponse<MentalWellnessAnalysisDto>> mentalAnalyzeGet() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(mentalService.analyze(userId)));
    }

    @PostMapping("/mental/analyze")
    public ResponseEntity<ApiResponse<MentalWellnessAnalysisDto>> mentalAnalyze() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(mentalService.analyze(userId)));
    }

    @GetMapping("/mental/analysis")
    public ResponseEntity<ApiResponse<MentalWellnessAnalysisDto>> mentalAnalysis() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(mentalService.analyze(userId)));
    }

    @PostMapping("/mental/analysis")
    public ResponseEntity<ApiResponse<MentalWellnessAnalysisDto>> mentalAnalysisPost() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(mentalService.analyze(userId)));
    }

    @GetMapping("/combined/analyze")
    public ResponseEntity<ApiResponse<CombinedWellnessAnalysisDto>> combinedAnalyzeGet() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(combinedService.analyze(userId)));
    }

    @PostMapping("/combined/analyze")
    public ResponseEntity<ApiResponse<CombinedWellnessAnalysisDto>> combinedAnalyze() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(combinedService.analyze(userId)));
    }

    @GetMapping("/combined/analysis")
    public ResponseEntity<ApiResponse<CombinedWellnessAnalysisDto>> combinedAnalysis() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(combinedService.analyze(userId)));
    }

    @PostMapping("/combined/analysis")
    public ResponseEntity<ApiResponse<CombinedWellnessAnalysisDto>> combinedAnalysisPost() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(combinedService.analyze(userId)));
    }
}
