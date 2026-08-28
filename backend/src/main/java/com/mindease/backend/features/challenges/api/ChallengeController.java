package com.mindease.backend.features.challenges.api;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.challenges.application.ChallengeService;
import com.mindease.backend.features.challenges.dto.ChallengeResponse;
import com.mindease.backend.security.AuthenticatedUser;

@RestController
@RequestMapping("/api/v1/challenges")
public class ChallengeController {

    private final ChallengeService service;

    public ChallengeController(ChallengeService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<ChallengeResponse>>> getAvailableChallenges() {
        return ResponseEntity.ok(ApiResponse.ok(service.getAvailableChallenges()));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<ChallengeResponse>> getChallengeById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getChallengeById(userId, id)));
    }

    @PostMapping("/{id}/start")
    public ResponseEntity<ApiResponse<ChallengeResponse>> startChallenge(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        ChallengeResponse response = service.startChallenge(userId, id);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @PutMapping("/user-challenges/{id}/progress")
    public ResponseEntity<ApiResponse<ChallengeResponse>> updateProgress(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.updateProgress(userId, id)));
    }

    @PutMapping("/user-challenges/{id}/complete")
    public ResponseEntity<ApiResponse<ChallengeResponse>> completeChallenge(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.completeChallenge(userId, id)));
    }

    @GetMapping("/active")
    public ResponseEntity<ApiResponse<List<ChallengeResponse>>> getActiveChallenges() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getActiveChallenges(userId)));
    }

    @GetMapping("/completed")
    public ResponseEntity<ApiResponse<List<ChallengeResponse>>> getCompletedChallenges() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getCompletedChallenges(userId)));
    }
}
