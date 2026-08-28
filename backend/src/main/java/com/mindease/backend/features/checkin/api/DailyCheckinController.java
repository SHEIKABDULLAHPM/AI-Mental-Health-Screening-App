package com.mindease.backend.features.checkin.api;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.checkin.application.DailyCheckinService;
import com.mindease.backend.features.checkin.dto.CheckinResponse;
import com.mindease.backend.features.checkin.dto.CreateCheckinRequest;
import com.mindease.backend.features.checkin.dto.UpdateCheckinRequest;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/check-ins")
public class DailyCheckinController {

    private final DailyCheckinService service;

    public DailyCheckinController(DailyCheckinService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<ApiResponse<CheckinResponse>> create(
            @Valid @RequestBody CreateCheckinRequest request) {
        String userId = AuthenticatedUser.currentId();
        CheckinResponse response = service.createCheckin(userId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @GetMapping("/today")
    public ResponseEntity<ApiResponse<CheckinResponse>> getToday() {
        String userId = AuthenticatedUser.currentId();
        CheckinResponse response = service.getTodayCheckin(userId);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<CheckinResponse>>> list(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size) {
        String userId = AuthenticatedUser.currentId();
        List<CheckinResponse> response = service.getCheckinHistory(userId, page, size);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<CheckinResponse>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getCheckinById(userId, id)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<CheckinResponse>> update(
            @PathVariable String id,
            @Valid @RequestBody UpdateCheckinRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.updateCheckin(userId, id, request)));
    }
}
