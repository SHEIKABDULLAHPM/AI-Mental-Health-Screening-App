package com.mindease.backend.wellness.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.wellness.application.WellnessProfileService;
import com.mindease.backend.wellness.dto.WellnessProfileDto;
import com.mindease.backend.wellness.application.MentalWellnessAnalysisService;
import org.springframework.web.bind.annotation.PostMapping;

@RestController
@RequestMapping("/api/v1/wellness-profile")
public class WellnessProfileController {

    private final WellnessProfileService service;

    public WellnessProfileController(WellnessProfileService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<WellnessProfileDto>> mine() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.currentUser(userId)));
    }
}
