package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableDeviceRepository;
import com.mindease.backend.features.physical.domain.WearableProvider;
import com.mindease.backend.features.physical.dto.CreateDeviceRequest;
import com.mindease.backend.features.physical.dto.DeviceResponse;
import com.mindease.backend.features.physical.dto.DeviceStatusRequest;

/**
 * Registration and lifecycle for wearable devices.
 *
 * <p>Ownership rule: every lookup is scoped by the authenticated
 * {@code userId}; a device belonging to another user is reported as
 * {@code NOT_FOUND} so existence is never leaked.</p>
 */
@Service
public class WearableDeviceService {

    private static final Logger log = LoggerFactory.getLogger(WearableDeviceService.class);

    private static final int MAX_CAPABILITIES = 32;

    private final WearableDeviceRepository devices;
    private final HealthDataValidator validator;

    public WearableDeviceService(WearableDeviceRepository devices, HealthDataValidator validator) {
        this.devices = devices;
        this.validator = validator;
    }

    /**
     * Registers a device or refreshes its profile. Registration is idempotent
     * per (user, deviceIdentifier): re-registering after a reinstall updates
     * the existing record instead of creating a duplicate.
     */
    public DeviceResponse register(String userId, CreateDeviceRequest request) {
        String batteryError = validator.validateBattery(request.batteryLevel());
        if (batteryError != null) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED, batteryError);
        }

        WearableDevice device = devices
                .findByUserIdAndDeviceIdentifier(userId, request.deviceIdentifier())
                .orElseGet(WearableDevice::new);

        boolean isNew = device.getId() == null;
        Instant now = Instant.now();
        device.setUserId(userId);
        device.setProvider(request.providerEnum());
        device.setDeviceIdentifier(request.deviceIdentifier());
        if (request.manufacturer() != null && !request.manufacturer().isBlank()) {
            device.setManufacturer(request.manufacturer().trim());
        }
        if (request.model() != null && !request.model().isBlank()) {
            device.setModel(request.model().trim());
        }
        if (request.firmwareVersion() != null && !request.firmwareVersion().isBlank()) {
            device.setFirmwareVersion(request.firmwareVersion().trim());
        }
        if (request.capabilities() != null) {
            device.setCapabilities(normalizeCapabilities(request.capabilities()));
        }
        if (request.batteryLevel() != null) {
            device.setBatteryLevel(request.batteryLevel());
        }
        if (isNew) {
            device.setConnectionStatus(ConnectionStatus.UNKNOWN);
            device.setCreatedAt(now);
        }
        device.setUpdatedAt(now);

        WearableDevice saved;
        try {
            saved = devices.save(device);
        } catch (DuplicateKeyException e) {
            // Concurrent registration of the same physical device: reload and retry once.
            saved = devices.findByUserIdAndDeviceIdentifier(userId, request.deviceIdentifier())
                    .orElseThrow(() -> new ApiException(ErrorCode.CONFLICT,
                            "Device registration could not be completed."));
        }
        log.info("Wearable device {} for provider {} {}", isNew ? "registered" : "updated",
                saved.getProvider(), saved.getId());
        return DeviceResponse.from(saved);
    }

    public List<DeviceResponse> list(String userId) {
        return devices.findByUserIdOrderByUpdatedAtDesc(userId).stream()
                .map(DeviceResponse::from)
                .toList();
    }

    public DeviceResponse get(String userId, String deviceId) {
        return DeviceResponse.from(requireOwned(userId, deviceId));
    }

    /**
     * Applies a device status patch. Only reported fields change — absent
     * fields keep their previous values (they are never defaulted).
     */
    public DeviceResponse updateStatus(String userId, String deviceId, DeviceStatusRequest request) {
        WearableDevice device = requireOwned(userId, deviceId);
        String batteryError = validator.validateBattery(request.batteryLevel());
        if (batteryError != null) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED, batteryError);
        }
        Instant now = Instant.now();
        if (request.batteryLevel() != null) {
            device.setBatteryLevel(request.batteryLevel());
        }
        if (request.charging() != null) {
            device.setCharging(request.charging());
        }
        if (request.connectionStatus() != null) {
            device.setConnectionStatus(request.connectionStatus());
            if (request.connectionStatus() == ConnectionStatus.CONNECTED) {
                device.setLastConnectedAt(now);
            }
        }
        if (request.firmwareVersion() != null && !request.firmwareVersion().isBlank()) {
            device.setFirmwareVersion(request.firmwareVersion().trim());
        }
        if (request.lastSeenAt() != null) {
            device.setLastSeenAt(request.lastSeenAt());
        } else {
            device.setLastSeenAt(now);
        }
        device.setUpdatedAt(now);
        return DeviceResponse.from(devices.save(device));
    }

    public void remove(String userId, String deviceId) {
        WearableDevice device = requireOwned(userId, deviceId);
        devices.delete(device);
        log.info("Wearable device {} removed", device.getId());
    }

    /**
     * Ownership-checked lookup used by the sync pipeline.
     *
     * @throws ApiException NOT_FOUND when the device does not exist or belongs
     *                      to a different user
     */
    public WearableDevice requireOwned(String userId, String deviceId) {
        return devices.findByIdAndUserId(deviceId, userId)
                .orElseThrow(() -> ApiException.notFound("Wearable device not found"));
    }

    /**
     * Replaces the device's capability identifier list after a registry update.
     * Ownership is enforced here rather than trusting the caller.
     */
    public void mergeCapabilities(String userId, String deviceId, List<String> capabilities) {
        WearableDevice device = requireOwned(userId, deviceId);
        device.setCapabilities(normalizeCapabilities(capabilities));
        device.setUpdatedAt(Instant.now());
        devices.save(device);
    }

    private List<String> normalizeCapabilities(List<String> capabilities) {
        LinkedHashSet<String> normalized = new LinkedHashSet<>();
        for (String capability : capabilities) {
            if (capability == null || capability.isBlank()) {
                continue;
            }
            normalized.add(capability.trim().toUpperCase(Locale.ROOT));
            if (normalized.size() >= MAX_CAPABILITIES) {
                break;
            }
        }
        return new ArrayList<>(normalized);
    }
}
