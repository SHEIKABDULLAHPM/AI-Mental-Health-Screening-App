package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.util.List;

import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableProvider;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Registration payload for a wearable device. The authenticated user id is
 * never part of this contract — the server derives it from the JWT context.
 */
public record CreateDeviceRequest(
        @NotBlank @Pattern(regexp = "FITPRO|HEALTH_CONNECT|SAMSUNG_HEALTH|WEAR_OS|MANUAL",
                message = "Unknown wearable provider") String provider,
        @NotBlank @Size(max = 128) String deviceIdentifier,
        @Size(max = 100) String manufacturer,
        @Size(max = 100) String model,
        @Size(max = 64) String firmwareVersion,
        List<String> capabilities,
        @Min(value = 0, message = "batteryLevel must be between 0 and 100")
        @Max(value = 100, message = "batteryLevel must be between 0 and 100")
        Integer batteryLevel) {

    public WearableProvider providerEnum() {
        return WearableProvider.valueOf(provider);
    }
}
