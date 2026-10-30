package com.mindease.backend.features.physical.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.physical.application.PhysicalInsightService;
import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.security.AuthenticatedUser;

/**
 * Mind–Body insights. Read-only and additive: if this endpoint fails the rest of
 * the physical wellness dashboard and the mental wellness flows are unaffected.
 */
@RestController
@RequestMapping("/api/v1/physical/insights")
public class PhysicalInsightController {

    private final PhysicalInsightService insights;

    public PhysicalInsightController(PhysicalInsightService insights) {
        this.insights = insights;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<InsightDtos.InsightsResponse>> insights() {
        return ResponseEntity.ok(ApiResponse.ok(
                insights.insights(AuthenticatedUser.currentId())));
    }
}
