package com.mindease.backend.features.mood.api;

import java.util.List;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.mood.application.MoodService;
import com.mindease.backend.features.mood.dto.AnalyzeMoodRequest;
import com.mindease.backend.features.mood.dto.AnalyzeMoodResponse;
import com.mindease.backend.features.mood.dto.CreateMoodRequest;
import com.mindease.backend.features.mood.dto.MoodResponse;
import com.mindease.backend.features.mood.dto.MoodStatisticsResponse;
import com.mindease.backend.features.mood.dto.MoodTrendResponse;
import com.mindease.backend.features.mood.dto.UpdateMoodRequest;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/moods")
public class MoodController {

    private final MoodService service;

    public MoodController(MoodService service) {
        this.service = service;
    }

    @PostMapping("/analyze")
    public ResponseEntity<ApiResponse<AnalyzeMoodResponse>> analyze(
            @Valid @RequestBody AnalyzeMoodRequest request) {
        String userId = AuthenticatedUser.currentId();
        AnalyzeMoodResponse response = service.analyzeMood(userId, request);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @GetMapping("/trends")
    public ResponseEntity<ApiResponse<List<MoodTrendResponse>>> trends(
            @RequestParam(defaultValue = "30") int days) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getMoodTrends(userId, days)));
    }

    @GetMapping("/trends/enhanced")
    public ResponseEntity<ApiResponse<Map<String, Object>>> enhancedTrends(
            @RequestParam(defaultValue = "30") int days) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getEnhancedTrends(userId, days)));
    }

    @GetMapping("/recent")
    public ResponseEntity<ApiResponse<List<MoodResponse>>> recent(
            @RequestParam(defaultValue = "5") int limit) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getRecentMoods(userId, limit)));
    }

    /**
     * Combined onboarding mood context (recent + trend + statistics) in one
     * round-trip so onboarding prefill needs a single HTTP call. Reuses the
     * exact same service calculations as the standalone endpoints.
     */
    @GetMapping("/onboarding-summary")
    public ResponseEntity<ApiResponse<Map<String, Object>>> onboardingSummary() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getOnboardingMoodSummary(userId)));
    }

    @GetMapping("/stats")
    public ResponseEntity<ApiResponse<MoodStatisticsResponse>> statistics() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getMoodStatistics(userId)));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<MoodResponse>> create(
            @Valid @RequestBody CreateMoodRequest request) {
        String userId = AuthenticatedUser.currentId();
        MoodResponse response = service.createMood(userId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<MoodResponse>>> list(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        String userId = AuthenticatedUser.currentId();
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), 100);
        return ResponseEntity.ok(ApiResponse.ok(service.getMoodEntries(userId, safePage, safeSize)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<MoodResponse>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getMoodById(userId, id)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<MoodResponse>> update(
            @PathVariable String id,
            @Valid @RequestBody UpdateMoodRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.updateMood(userId, id, request)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> delete(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        service.deleteMood(userId, id);
        return ResponseEntity.ok(ApiResponse.ok());
    }
}
