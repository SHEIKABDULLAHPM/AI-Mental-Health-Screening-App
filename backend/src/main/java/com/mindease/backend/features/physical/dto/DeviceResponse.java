package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.util.List;

import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableProvider;

public record DeviceResponse(
        String id,
        WearableProvider provider,
        String manufacturer,
        String model,
        String firmwareVersion,
        String deviceIdentifier,
        List<String> capabilities,
        ConnectionStatus connectionStatus,
        Integer batteryLevel,
        Boolean charging,
        Instant lastConnectedAt,
        Instant lastSeenAt,
        Instant lastSyncedAt,
        Instant createdAt,
        Instant updatedAt) {

    public static DeviceResponse from(WearableDevice device) {
        return new DeviceResponse(
                device.getId(),
                device.getProvider(),
                device.getManufacturer(),
                device.getModel(),
                device.getFirmwareVersion(),
                device.getDeviceIdentifier(),
                device.getCapabilities(),
                device.getConnectionStatus(),
                device.getBatteryLevel(),
                device.getCharging(),
                device.getLastConnectedAt(),
                device.getLastSeenAt(),
                device.getLastSyncedAt(),
                device.getCreatedAt(),
                device.getUpdatedAt());
    }
}
