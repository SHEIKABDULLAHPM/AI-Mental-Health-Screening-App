package com.mindease.backend.features.physical.api;

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
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.physical.application.WearableDeviceService;
import com.mindease.backend.features.physical.dto.CreateDeviceRequest;
import com.mindease.backend.features.physical.dto.DeviceResponse;
import com.mindease.backend.features.physical.dto.DeviceStatusRequest;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

/**
 * Wearable device registration and status. The authenticated user is always
 * resolved from the JWT context — no client-supplied user id is ever accepted.
 */
@RestController
@RequestMapping("/api/v1/wearables")
public class WearableController {

    private final WearableDeviceService devices;

    public WearableController(WearableDeviceService devices) {
        this.devices = devices;
    }

    @PostMapping
    public ResponseEntity<ApiResponse<DeviceResponse>> register(
            @Valid @RequestBody CreateDeviceRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.created(devices.register(userId, request)));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<DeviceResponse>>> list() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(devices.list(userId)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<DeviceResponse>> get(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(devices.get(userId, id)));
    }

    @PutMapping("/{id}/status")
    public ResponseEntity<ApiResponse<DeviceResponse>> updateStatus(
            @PathVariable String id, @Valid @RequestBody DeviceStatusRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(devices.updateStatus(userId, id, request)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> remove(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        devices.remove(userId, id);
        return ResponseEntity.ok(ApiResponse.ok());
    }
}
