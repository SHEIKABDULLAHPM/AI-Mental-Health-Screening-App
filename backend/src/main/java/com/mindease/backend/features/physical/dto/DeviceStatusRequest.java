package com.mindease.backend.features.physical.dto;

import java.time.Instant;

import com.mindease.backend.features.physical.domain.ConnectionStatus;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

/**
 * Device status update (battery / connection / firmware). Every field is
 * optional; {@code null} means "not reported", never an implied default.
 */
public record DeviceStatusRequest(
        @Min(value = 0, message = "batteryLevel must be between 0 and 100")
        @Max(value = 100, message = "batteryLevel must be between 0 and 100")
        Integer batteryLevel,
        Boolean charging,
        ConnectionStatus connectionStatus,
        String firmwareVersion,
        Instant lastSeenAt) {
}
