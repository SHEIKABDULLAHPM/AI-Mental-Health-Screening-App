package com.mindease.backend.features.physical.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.physical.application.PhysicalSyncService;
import com.mindease.backend.features.physical.application.PhysicalWellnessService;
import com.mindease.backend.features.physical.dto.ActivityHistoryResponse;
import com.mindease.backend.features.physical.dto.ExerciseHistoryResponse;
import com.mindease.backend.features.physical.dto.HeartRateResponse;
import com.mindease.backend.features.physical.dto.PhysicalTodayResponse;
import com.mindease.backend.features.physical.dto.SleepHistoryResponse;
import com.mindease.backend.features.physical.dto.SyncRequest;
import com.mindease.backend.features.physical.dto.SyncResponse;
import com.mindease.backend.features.physical.dto.WeeklySummaryResponse;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

/**
 * Physical Wellness data API: synchronization ingest plus the dashboard and
 * history reads. No raw BLE/protocol endpoints are exposed.
 */
@RestController
@RequestMapping("/api/v1/physical")
public class PhysicalWellnessController {

    private final PhysicalSyncService syncService;
    private final PhysicalWellnessService wellnessService;

    public PhysicalWellnessController(PhysicalSyncService syncService,
                                      PhysicalWellnessService wellnessService) {
        this.syncService = syncService;
        this.wellnessService = wellnessService;
    }

    @PostMapping("/sync")
    public ResponseEntity<ApiResponse<SyncResponse>> sync(
            @Valid @RequestBody SyncRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(syncService.sync(userId, request)));
    }

    @GetMapping("/today")
    public ResponseEntity<ApiResponse<PhysicalTodayResponse>> today() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(wellnessService.today(userId)));
    }

    @GetMapping("/activity")
    public ResponseEntity<ApiResponse<ActivityHistoryResponse>> activity(
            @RequestParam(required = false) Integer days) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(wellnessService.activity(userId, days)));
    }

    @GetMapping("/heart-rate")
    public ResponseEntity<ApiResponse<HeartRateResponse>> heartRate(
            @RequestParam(required = false) Integer hours) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(wellnessService.heartRate(userId, hours)));
    }

    @GetMapping("/sleep")
    public ResponseEntity<ApiResponse<SleepHistoryResponse>> sleep(
            @RequestParam(required = false) Integer limit) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(wellnessService.sleep(userId, limit)));
    }

    @GetMapping("/exercise")
    public ResponseEntity<ApiResponse<ExerciseHistoryResponse>> exercise(
            @RequestParam(required = false) Integer limit) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(wellnessService.exercise(userId, limit)));
    }

    @GetMapping("/summary")
    public ResponseEntity<ApiResponse<WeeklySummaryResponse>> weeklySummary() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(wellnessService.weekly(userId)));
    }
}
