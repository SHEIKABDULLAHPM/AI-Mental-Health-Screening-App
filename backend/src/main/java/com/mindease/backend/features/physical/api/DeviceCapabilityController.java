package com.mindease.backend.features.physical.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.physical.application.DeviceCapabilityService;
import com.mindease.backend.features.physical.dto.DeviceCapabilityDtos;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

/**
 * Capability registry for a device. Verification status is server-owned: a
 * client report can add observations, but cannot self-certify hardware support.
 */
@RestController
@RequestMapping("/api/v1/wearables/{id}/capabilities")
public class DeviceCapabilityController {

    private final DeviceCapabilityService capabilities;

    public DeviceCapabilityController(DeviceCapabilityService capabilities) {
        this.capabilities = capabilities;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<DeviceCapabilityDtos.CapabilityListResponse>> list(
            @PathVariable String id) {
        return ResponseEntity.ok(ApiResponse.ok(
                capabilities.list(AuthenticatedUser.currentId(), id)));
    }

    @PutMapping
    public ResponseEntity<ApiResponse<DeviceCapabilityDtos.CapabilityListResponse>> report(
            @PathVariable String id,
            @Valid @RequestBody DeviceCapabilityDtos.CapabilityReportRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(
                capabilities.report(AuthenticatedUser.currentId(), id, request)));
    }
}
