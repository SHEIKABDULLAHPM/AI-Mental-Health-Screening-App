package com.mindease.backend.features.challenges.api;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.challenges.application.ChallengeService;
import com.mindease.backend.features.challenges.dto.BadgeResponse;
import com.mindease.backend.features.challenges.dto.ChallengeHomeResponse;
import com.mindease.backend.features.challenges.dto.ChallengeResponse;
import com.mindease.backend.features.challenges.dto.GameResultRequest;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.security.UserTimeZoneHolder;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/challenges")
public class ChallengeController {

    private final ChallengeService service;

    public ChallengeController(ChallengeService service) {
        this.service = service;
    }

    /**
     * Aggregated data for the Challenges home screen.
     * Uses the explicit zone query param if provided, otherwise falls back to
     * the X-User-Timezone request header.
     */
    @GetMapping("/home")
    public ResponseEntity<ApiResponse<ChallengeHomeResponse>> home(
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        return ResponseEntity.ok(ApiResponse.ok(service.getHome(userId, effectiveZone)));
    }

    /** Available challenges for the authenticated user. */
    @GetMapping
    public ResponseEntity<ApiResponse<List<ChallengeResponse>>> getAvailable(
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        ChallengeHomeResponse home = service.getHome(userId, effectiveZone);
        return ResponseEntity.ok(ApiResponse.ok(home.active()));
    }

    /** A single challenge with the user's current progress. */
    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<ChallengeResponse>> getById(
            @PathVariable String id,
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        ChallengeResponse response = service.getChallenge(userId, id, effectiveZone);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    /** Start a challenge for the current period (idempotent). */
    @PostMapping("/{id}/start")
    public ResponseEntity<ApiResponse<ChallengeResponse>> start(
            @PathVariable String id,
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        ChallengeResponse response = service.startChallenge(userId, id, effectiveZone);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    /** Submit a game result for challenge validation and progress. */
    @PostMapping("/{id}/complete")
    public ResponseEntity<ApiResponse<ChallengeResponse>> completeGame(
            @PathVariable String id,
            @Valid @RequestBody GameResultRequest result,
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        ChallengeResponse response = service.submitGameResult(userId, id, result, effectiveZone);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    /** Submit progress for a non-game challenge activity. */
    @PostMapping("/{id}/progress")
    public ResponseEntity<ApiResponse<ChallengeResponse>> submitProgress(
            @PathVariable String id,
            @RequestParam String sourceRecordId,
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        ChallengeResponse response = service.submitProgress(userId, id, sourceRecordId, effectiveZone);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    /** Badges earned by the authenticated user. */
    @GetMapping("/badges")
    public ResponseEntity<ApiResponse<List<BadgeResponse>>> badges() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getBadges(userId)));
    }

    /** Challenge history (completed + expired), paginated. */
    @GetMapping("/history")
    public ResponseEntity<ApiResponse<List<ChallengeResponse>>> history(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        return ResponseEntity.ok(ApiResponse.ok(service.getHistory(userId, effectiveZone, page, size)));
    }

    /** Active challenge progress summary. */
    @GetMapping("/progress")
    public ResponseEntity<ApiResponse<List<ChallengeResponse>>> progress(
            @RequestParam(required = false) String zone) {
        String userId = AuthenticatedUser.currentId();
        String effectiveZone = resolveZone(zone);
        return ResponseEntity.ok(ApiResponse.ok(service.getActiveProgress(userId, effectiveZone)));
    }

    private static String resolveZone(String explicit) {
        if (explicit != null && !explicit.isBlank()) {
            return explicit;
        }
        return UserTimeZoneHolder.get();
    }
}
