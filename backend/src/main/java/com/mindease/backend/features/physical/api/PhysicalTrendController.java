package com.mindease.backend.features.physical.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.physical.application.PhysicalTrendService;
import com.mindease.backend.features.physical.dto.TrendDtos;
import com.mindease.backend.security.AuthenticatedUser;

/** Daily/weekly/monthly trend series built only from stored records. */
@RestController
@RequestMapping("/api/v1/physical/trends")
public class PhysicalTrendController {

    private final PhysicalTrendService trends;

    public PhysicalTrendController(PhysicalTrendService trends) {
        this.trends = trends;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<TrendDtos.TrendsResponse>> trends(
            @RequestParam(required = false) Integer days) {
        return ResponseEntity.ok(ApiResponse.ok(
                trends.trends(AuthenticatedUser.currentId(), days)));
    }
}
