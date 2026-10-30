package com.mindease.backend.wellness.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.wellness.application.CombinedInsightService;
import com.mindease.backend.wellness.dto.CombinedInsightDto;
import com.mindease.backend.wellness.application.MentalWellnessAnalysisService;
import com.mindease.backend.wellness.application.CombinedWellnessAnalysisService;
import org.springframework.web.bind.annotation.PostMapping;

/**
 * Combined mental + physical insight for the dashboard.
 *
 * <p>Returns 200 with {@code available=false} when the user has no wellness
 * profile yet, so the client can simply hide the card instead of rendering an
 * error for a normal pre-onboarding state.</p>
 */
@RestController
@RequestMapping("/api/v1/wellness")
public class CombinedInsightController {

    private final CombinedInsightService service;

    public CombinedInsightController(CombinedInsightService service) {
        this.service = service;
    }

    @GetMapping("/combined-insight")
    public ResponseEntity<ApiResponse<CombinedInsightDto>> combined() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.combined(userId)));
    }
}
