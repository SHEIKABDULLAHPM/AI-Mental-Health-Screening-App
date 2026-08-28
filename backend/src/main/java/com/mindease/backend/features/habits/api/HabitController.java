package com.mindease.backend.features.habits.api;

import java.util.List;

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
import com.mindease.backend.features.habits.application.HabitService;
import com.mindease.backend.features.habits.domain.HabitRecord;
import com.mindease.backend.features.habits.dto.CreateHabitRequest;
import com.mindease.backend.features.habits.dto.HabitRecordRequest;
import com.mindease.backend.features.habits.dto.HabitResponse;
import com.mindease.backend.features.habits.dto.UpdateHabitRequest;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/habits")
public class HabitController {

    private final HabitService service;

    public HabitController(HabitService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<ApiResponse<HabitResponse>> create(
            @Valid @RequestBody CreateHabitRequest request) {
        String userId = AuthenticatedUser.currentId();
        HabitResponse response = service.createHabit(userId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<HabitResponse>>> list() {
        String userId = AuthenticatedUser.currentId();
        List<HabitResponse> response = service.getUserHabits(userId);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @GetMapping("/weekly-progress")
    public ResponseEntity<ApiResponse<List<HabitResponse>>> weeklyProgress() {
        String userId = AuthenticatedUser.currentId();
        List<HabitResponse> response = service.getWeeklyProgress(userId);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @GetMapping("/monthly-progress")
    public ResponseEntity<ApiResponse<List<HabitResponse>>> monthlyProgress() {
        String userId = AuthenticatedUser.currentId();
        List<HabitResponse> response = service.getMonthlyProgress(userId);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<HabitResponse>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        HabitResponse response = service.getHabitById(userId, id);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<HabitResponse>> update(
            @PathVariable String id,
            @Valid @RequestBody UpdateHabitRequest request) {
        String userId = AuthenticatedUser.currentId();
        HabitResponse response = service.updateHabit(userId, id, request);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> delete(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        service.deleteHabit(userId, id);
        return ResponseEntity.ok(ApiResponse.ok());
    }

    @PostMapping("/{id}/records")
    public ResponseEntity<ApiResponse<HabitResponse>> recordCompletion(
            @PathVariable String id,
            @Valid @RequestBody HabitRecordRequest request) {
        String userId = AuthenticatedUser.currentId();
        HabitResponse response = service.recordCompletion(userId, id, request);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @GetMapping("/{id}/records")
    public ResponseEntity<ApiResponse<List<HabitRecord>>> getHistory(
            @PathVariable String id,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        String userId = AuthenticatedUser.currentId();
        List<HabitRecord> response = service.getHabitHistory(userId, id, page, size);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }
}
