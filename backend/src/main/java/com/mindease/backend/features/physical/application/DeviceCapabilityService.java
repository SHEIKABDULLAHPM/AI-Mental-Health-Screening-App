package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.domain.CapabilityRetrievalMethod;
import com.mindease.backend.features.physical.domain.CapabilitySupportStatus;
import com.mindease.backend.features.physical.domain.DeviceCapability;
import com.mindease.backend.features.physical.domain.DeviceCapabilityRepository;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableProvider;
import com.mindease.backend.features.physical.dto.DeviceCapabilityDtos;

/**
 * Device capability registry.
 *
 * <p>Honesty rules enforced here:</p>
 * <ul>
 *   <li>A capability is only {@code SUPPORTED_VERIFIED} after an on-device
 *       validation pass. Client reports can never promote it — a report that
 *       claims verification is downgraded to {@code SUPPORTED_UNVERIFIED}.</li>
 *   <li>Capabilities the provider is known not to expose (e.g. GPS routes on
 *       FitPro) are recorded as explicitly {@code UNSUPPORTED} with a
 *       limitation note, so the UI can say so instead of hiding it.</li>
 *   <li>Unknown capabilities are rejected rather than stored silently.</li>
 * </ul>
 */
@Service
public class DeviceCapabilityService {

    private static final Logger log = LoggerFactory.getLogger(DeviceCapabilityService.class);

    private static final List<String> FITPRO_UNSUPPORTED = List.of(
            "GPS_ROUTE", "BODY_FAT", "MUSCLE_MASS", "HEART_RATE_VARIABILITY",
            "RESTING_HEART_RATE", "EXERCISE");

    /**
     * Metrics the FitPro protocol is documented to carry (Gadgetbridge
     * FitProDeviceSupport / FitProConstants, MFitX). They are seeded as
     * supported-but-unverified: the watch can measure them, but nothing is
     * marked verified until a real record arrives from this unit.
     */
    private static final Set<String> FITPRO_PROTOCOL_METRICS = Set.of(
            "STEPS", "DISTANCE", "CALORIES", "ACTIVE_MINUTES",
            "HEART_RATE", "SLEEP", "SLEEP_STAGES");

    private static final String PROTOCOL_NOT_OBSERVED =
            "The FitPro protocol defines this metric, but no value has been received "
                    + "from this watch yet.";

    private static final String VERIFIED_BY_RECORD =
            "Confirmed by a record measured on this watch.";

    private static final Map<String, String> FITPRO_LIMITATIONS = Map.of(
            "GPS_ROUTE", "The FitPro protocol exposes no route data; the watch has no usable GPS source.",
            "BODY_FAT", "No verified body-composition sensor is exposed by this device.",
            "MUSCLE_MASS", "No verified body-composition sensor is exposed by this device.",
            "HEART_RATE_VARIABILITY", "The FitPro frame layout does not provide a verified HRV measure.",
            "RESTING_HEART_RATE", "The FitPro protocol carries spot heart-rate samples but no verified resting-heart-rate field.",
            "EXERCISE", "The FitPro protocol slice exposes no structured workout sessions.",
            "SLEEP_STAGES", "Only raw stage codes are reported; their mapping to light/deep/REM is unverified.",
            "SPO2", "The heart-rate frame carries a blood-oxygen byte at the same offset Gadgetbridge decodes as SpO2; it becomes verified once this watch reports a reading in the plausible range.");

    private final DeviceCapabilityRepository capabilities;
    private final WearableDeviceService devices;
    private final CapabilityCatalog catalog;

    public DeviceCapabilityService(DeviceCapabilityRepository capabilities,
                                   WearableDeviceService devices,
                                   CapabilityCatalog catalog) {
        this.capabilities = capabilities;
        this.devices = devices;
        this.catalog = catalog;
    }

    public DeviceCapabilityDtos.CapabilityListResponse list(String userId, String deviceId) {
        WearableDevice device = devices.requireOwned(userId, deviceId);
        List<DeviceCapability> stored = capabilities
                .findByUserIdAndDeviceIdOrderByMetricAsc(userId, deviceId);
        if (stored.isEmpty()) {
            stored = seedFromDevice(userId, device);
        } else {
            stored = ensureCatalogCoverage(userId, device, stored);
        }
        stored = reconcileProtocolSeeds(userId, device, stored);
        List<DeviceCapabilityDtos.CapabilityResponse> mapped = new ArrayList<>();
        for (DeviceCapability capability : stored) {
            mapped.add(map(capability));
        }
        mapped.sort((a, b) -> a.label().compareToIgnoreCase(b.label()));
        return new DeviceCapabilityDtos.CapabilityListResponse(
                device.getId(),
                device.getModel(),
                device.getFirmwareVersion(),
                mapped,
                buildNotes(device, mapped));
    }

    public DeviceCapabilityDtos.CapabilityListResponse report(
            String userId, String deviceId, DeviceCapabilityDtos.CapabilityReportRequest request) {
        WearableDevice device = devices.requireOwned(userId, deviceId);
        List<DeviceCapabilityDtos.CapabilityInput> inputs = request.capabilities() == null
                ? List.of() : request.capabilities();
        if (inputs.size() > 48) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "A capability report may contain at most 48 entries");
        }
        Instant now = Instant.now();
        for (DeviceCapabilityDtos.CapabilityInput input : inputs) {
            CapabilityCatalog.Definition definition = catalog.find(input.metric())
                    .orElseThrow(() -> new ApiException(ErrorCode.BAD_REQUEST,
                            "Unknown capability: " + input.metric()));
            CapabilitySupportStatus status = parseStatus(input.supportStatus());
            // A provider that is known not to expose a metric stays unsupported,
            // regardless of what the client reports. This stops a buggy (or
            // over-eager) client from promoting, say, body composition on a
            // watch with no such sensor.
            boolean providerCannotMeasure = device.getProvider() == WearableProvider.FITPRO
                    && FITPRO_UNSUPPORTED.contains(definition.id());
            if (providerCannotMeasure) {
                status = CapabilitySupportStatus.UNSUPPORTED;
            } else if (status == CapabilitySupportStatus.SUPPORTED_VERIFIED) {
                // Clients cannot self-certify hardware verification.
                status = CapabilitySupportStatus.SUPPORTED_UNVERIFIED;
            }
            DeviceCapability capability = capabilities
                    .findByUserIdAndDeviceIdAndMetric(userId, deviceId, definition.id())
                    .orElseGet(DeviceCapability::new);
            boolean alreadyVerified = !providerCannotMeasure
                    && capability.getSupportStatus() == CapabilitySupportStatus.SUPPORTED_VERIFIED;
            if (alreadyVerified) {
                // A verified capability is the strongest evidence the server
                // has. A later client report may not downgrade it or replace
                // the evidence note.
                status = CapabilitySupportStatus.SUPPORTED_VERIFIED;
            }
            capability.setUserId(userId);
            capability.setDeviceId(deviceId);
            capability.setMetric(definition.id());
            capability.setDeviceModel(device.getModel());
            capability.setFirmwareVersion(device.getFirmwareVersion());
            capability.setSupportStatus(status);
            if (providerCannotMeasure) {
                capability.setRetrievalMethod(CapabilityRetrievalMethod.NONE);
                // The server's documented reason wins over client wording.
                capability.setLimitations(FITPRO_LIMITATIONS.get(definition.id()));
            } else if (!alreadyVerified) {
                capability.setRetrievalMethod(parseRetrieval(input.retrievalMethod(), device));
                if (input.limitations() != null && !input.limitations().isBlank()) {
                    capability.setLimitations(input.limitations().trim());
                }
            }
            capability.setUpdatedAt(now);
            capabilities.save(capability);
        }
        syncDeviceCapabilityList(userId, device);
        log.info("Capability report for device {}: {} entries", deviceId, inputs.size());
        return list(userId, deviceId);
    }

    /** Reads a single capability, or {@code null} when it was never catalogued. */
    public DeviceCapability get(String userId, String deviceId, String metricId) {
        return capabilities.findByUserIdAndDeviceIdAndMetric(userId, deviceId, metricId)
                .orElse(null);
    }

    /**
     * Maps the device's plain capability list onto dashboard-visible metric
     * support. Explicit registry entries win; otherwise the historical list is
     * used, which keeps existing devices backward compatible.
     */
    public Set<String> supportedMetrics(String userId, String deviceId) {
        Set<String> supported = new LinkedHashSet<>();
        for (DeviceCapability capability : capabilities
                .findByUserIdAndDeviceIdOrderByMetricAsc(userId, deviceId)) {
            if (capability.getSupportStatus() == CapabilitySupportStatus.SUPPORTED_VERIFIED
                    || capability.getSupportStatus() == CapabilitySupportStatus.SUPPORTED_UNVERIFIED) {
                supported.add(capability.getMetric());
            }
        }
        return supported;
    }

    /**
     * Registry view for the dashboard. Seeds the catalog when the device has
     * never reported capabilities, so a protocol-defined metric is not
     * misreported as unsupported just because no sync has happened yet.
     */
    public Set<String> supportedMetrics(String userId, WearableDevice device) {
        if (device == null) {
            return Set.of();
        }
        List<DeviceCapability> stored = capabilities
                .findByUserIdAndDeviceIdOrderByMetricAsc(userId, device.getId());
        if (stored.isEmpty()) {
            stored = seedFromDevice(userId, device);
        } else {
            stored = reconcileProtocolSeeds(userId, device,
                    ensureCatalogCoverage(userId, device, stored));
        }
        Set<String> supported = new LinkedHashSet<>();
        for (DeviceCapability capability : stored) {
            if (capability.getSupportStatus() == CapabilitySupportStatus.SUPPORTED_VERIFIED
                    || capability.getSupportStatus() == CapabilitySupportStatus.SUPPORTED_UNVERIFIED) {
                supported.add(capability.getMetric());
            }
        }
        return supported;
    }

    /**
     * Server-side verification from a real record.
     *
     * <p>Clients still cannot self-certify: only this method, called after the
     * backend stored a device-measured record for this exact device, may
     * promote a status. Metrics the provider is known not to expose are never
     * promoted.</p>
     */
    public void markVerified(String userId, String deviceId, String metric, String evidenceNote) {
        if (metric == null) {
            return;
        }
        String id = metric.trim().toUpperCase(Locale.ROOT);
        if (FITPRO_UNSUPPORTED.contains(id)) {
            return;
        }
        DeviceCapability capability = capabilities
                .findByUserIdAndDeviceIdAndMetric(userId, deviceId, id)
                .orElse(null);
        if (capability == null
                || capability.getSupportStatus() == CapabilitySupportStatus.SUPPORTED_VERIFIED) {
            return;
        }
        capability.setSupportStatus(CapabilitySupportStatus.SUPPORTED_VERIFIED);
        if (capability.getRetrievalMethod() == null
                || capability.getRetrievalMethod() == CapabilityRetrievalMethod.NONE) {
            capability.setRetrievalMethod(CapabilityRetrievalMethod.VENDOR_PROTOCOL);
        }
        capability.setLimitations(
                evidenceNote == null || evidenceNote.isBlank()
                        ? VERIFIED_BY_RECORD : evidenceNote);
        capability.setLastVerifiedAt(Instant.now());
        capability.setUpdatedAt(Instant.now());
        capabilities.save(capability);
        log.info("Capability {} verified for device {} from an observed record", id, deviceId);
    }

    /**
     * Brings legacy UNKNOWN rows in line with what the FitPro protocol can
     * actually deliver. Verified rows are never downgraded, and metrics with
     * evidence keep their evidence note.
     */
    private List<DeviceCapability> reconcileProtocolSeeds(
            String userId, WearableDevice device, List<DeviceCapability> stored) {
        if (device.getProvider() != WearableProvider.FITPRO) {
            return stored;
        }
        Instant now = Instant.now();
        for (DeviceCapability capability : stored) {
            if (capability.getSupportStatus() != CapabilitySupportStatus.UNKNOWN) {
                continue;
            }
            String metric = capability.getMetric();
            if (FITPRO_UNSUPPORTED.contains(metric)) {
                capability.setSupportStatus(CapabilitySupportStatus.UNSUPPORTED);
                capability.setRetrievalMethod(CapabilityRetrievalMethod.NONE);
                capability.setLimitations(FITPRO_LIMITATIONS.get(metric));
            } else if (FITPRO_PROTOCOL_METRICS.contains(metric)) {
                capability.setSupportStatus(CapabilitySupportStatus.SUPPORTED_UNVERIFIED);
                capability.setRetrievalMethod(CapabilityRetrievalMethod.VENDOR_PROTOCOL);
                capability.setLimitations(PROTOCOL_NOT_OBSERVED);
            } else {
                continue;
            }
            capability.setUpdatedAt(now);
            capabilities.save(capability);
        }
        return stored;
    }

    private List<DeviceCapability> seedFromDevice(String userId, WearableDevice device) {
        return seedFromDevice(userId, device, Set.of());
    }

    /**
     * Seeds the default capability set, skipping metrics that already have a
     * stored row. Skipping matters: {@code uq_device_metric} is unique, so
     * re-saving an existing metric would fail the whole request.
     */
    private List<DeviceCapability> seedFromDevice(String userId, WearableDevice device,
                                                  Set<String> skipMetrics) {
        Instant now = Instant.now();
        Set<String> reported = new LinkedHashSet<>();
        if (device.getCapabilities() != null) {
            for (String metric : device.getCapabilities()) {
                catalog.find(metric).ifPresent(def -> reported.add(def.id()));
            }
        }
        List<DeviceCapability> seeded = new ArrayList<>();
        for (CapabilityCatalog.Definition definition : catalog.all().values()) {
            if (skipMetrics.contains(definition.id())) {
                continue;
            }
            CapabilitySupportStatus status;
            CapabilityRetrievalMethod method;
            String limitations = null;
            if (device.getProvider() == WearableProvider.FITPRO
                    && FITPRO_UNSUPPORTED.contains(definition.id())) {
                status = CapabilitySupportStatus.UNSUPPORTED;
                method = CapabilityRetrievalMethod.NONE;
                limitations = FITPRO_LIMITATIONS.get(definition.id());
            } else if (isStandardGatt(definition.id()) && device.getProvider() == WearableProvider.FITPRO) {
                status = CapabilitySupportStatus.SUPPORTED_UNVERIFIED;
                method = CapabilityRetrievalMethod.GATT_STANDARD;
                limitations = "Reported by the standard GATT service; sample values still need "
                        + "confirmation against this firmware.";
            } else if (device.getProvider() == WearableProvider.FITPRO
                    && FITPRO_PROTOCOL_METRICS.contains(definition.id())) {
                status = CapabilitySupportStatus.SUPPORTED_UNVERIFIED;
                method = CapabilityRetrievalMethod.VENDOR_PROTOCOL;
                limitations = PROTOCOL_NOT_OBSERVED;
            } else if (reported.contains(definition.id())) {
                status = CapabilitySupportStatus.SUPPORTED_UNVERIFIED;
                method = device.getProvider() == WearableProvider.FITPRO
                        ? CapabilityRetrievalMethod.VENDOR_PROTOCOL
                        : CapabilityRetrievalMethod.MANUAL_ENTRY;
                limitations = FITPRO_LIMITATIONS.get(definition.id());
            } else if (isManualLifestyle(definition.id())) {
                status = CapabilitySupportStatus.SUPPORTED_UNVERIFIED;
                method = CapabilityRetrievalMethod.MANUAL_ENTRY;
                limitations = "Available through manual entry; no wearable measurement required.";
            } else {
                status = CapabilitySupportStatus.UNKNOWN;
                method = CapabilityRetrievalMethod.NONE;
                // Keep the documented reason for an unknown metric instead of
                // an unexplained blank row (e.g. the unverified SpO2 byte).
                if (device.getProvider() == WearableProvider.FITPRO) {
                    limitations = FITPRO_LIMITATIONS.get(definition.id());
                }
            }
            DeviceCapability capability = new DeviceCapability();
            capability.setUserId(userId);
            capability.setDeviceId(device.getId());
            capability.setMetric(definition.id());
            capability.setDeviceModel(device.getModel());
            capability.setFirmwareVersion(device.getFirmwareVersion());
            capability.setSupportStatus(status);
            capability.setRetrievalMethod(method);
            capability.setLimitations(limitations);
            capability.setUpdatedAt(now);
            seeded.add(capabilities.save(capability));
        }
        return seeded;
    }

    private List<DeviceCapability> ensureCatalogCoverage(
            String userId, WearableDevice device, List<DeviceCapability> stored) {
        Set<String> present = new LinkedHashSet<>();
        for (DeviceCapability capability : stored) {
            present.add(capability.getMetric());
        }
        boolean missing = false;
        for (String id : catalog.all().keySet()) {
            if (!present.contains(id)) {
                missing = true;
                break;
            }
        }
        if (!missing) {
            return stored;
        }
        // Only the absent metrics are created; existing rows keep their
        // recorded status, limitations and verification timestamps.
        List<DeviceCapability> added = seedFromDevice(userId, device, present);
        Map<String, DeviceCapability> byMetric = new LinkedHashMap<>();
        for (DeviceCapability capability : stored) {
            byMetric.put(capability.getMetric(), capability);
        }
        for (DeviceCapability capability : added) {
            byMetric.putIfAbsent(capability.getMetric(), capability);
        }
        List<DeviceCapability> merged = new ArrayList<>(byMetric.values());
        merged.sort((a, b) -> a.getMetric().compareTo(b.getMetric()));
        return merged;
    }

    private void syncDeviceCapabilityList(String userId, WearableDevice device) {
        Set<String> supported = supportedMetrics(userId, device.getId());
        if (supported.isEmpty()) {
            return;
        }
        Set<String> merged = new LinkedHashSet<>(supported);
        if (device.getCapabilities() != null) {
            merged.addAll(device.getCapabilities());
        }
        devices.mergeCapabilities(userId, device.getId(), new ArrayList<>(merged));
    }

    private DeviceCapabilityDtos.CapabilityResponse map(DeviceCapability capability) {
        CapabilityCatalog.Definition definition = catalog.find(capability.getMetric())
                .orElse(new CapabilityCatalog.Definition(
                        capability.getMetric(), capability.getMetric(), "", false));
        CapabilitySupportStatus status = capability.getSupportStatus() == null
                ? CapabilitySupportStatus.UNKNOWN : capability.getSupportStatus();
        String verification = switch (status) {
            case SUPPORTED_VERIFIED -> "VERIFIED_ON_DEVICE";
            case SUPPORTED_UNVERIFIED -> "UNVERIFIED";
            case UNSUPPORTED -> "NOT_SUPPORTED";
            case TEMPORARILY_UNAVAILABLE -> "TEMPORARILY_UNAVAILABLE";
            case UNKNOWN -> "UNKNOWN";
        };
        return new DeviceCapabilityDtos.CapabilityResponse(
                definition.id(),
                definition.label(),
                definition.unit(),
                status.name(),
                capability.getRetrievalMethod() == null
                        ? CapabilityRetrievalMethod.NONE.name()
                        : capability.getRetrievalMethod().name(),
                verification,
                capability.getLimitations(),
                capability.getLastVerifiedAt(),
                capability.getUpdatedAt());
    }

    private List<String> buildNotes(WearableDevice device,
                                    List<DeviceCapabilityDtos.CapabilityResponse> mapped) {
        List<String> notes = new ArrayList<>();
        long verified = mapped.stream()
                .filter(item -> "SUPPORTED_VERIFIED".equals(item.supportStatus()))
                .count();
        long unsupported = mapped.stream()
                .filter(item -> "UNSUPPORTED".equals(item.supportStatus()))
                .count();
        notes.add(verified == 0
                ? "No capability has been verified on this watch yet; supported "
                        + "metrics are shown as unverified."
                : verified + " capabilities verified by real records from this watch.");
        if (unsupported > 0) {
            notes.add(unsupported + " capabilities are explicitly unsupported by this device.");
        }
        if (device.getFirmwareVersion() != null) {
            notes.add("Firmware: " + device.getFirmwareVersion());
        }
        notes.add("The app cannot self-certify a capability. The server marks one verified "
                + "only after this watch delivers a real measurement.");
        return notes;
    }

    private static boolean isStandardGatt(String metric) {
        return "BATTERY_LEVEL".equals(metric)
                || "FIRMWARE_INFO".equals(metric)
                || "DEVICE_MODEL".equals(metric);
    }

    private static boolean isManualLifestyle(String metric) {
        return "BODY_WEIGHT".equals(metric)
                || "BODY_HEIGHT".equals(metric)
                || "HYDRATION".equals(metric);
    }

    private static CapabilitySupportStatus parseStatus(String raw) {
        if (raw == null || raw.isBlank()) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "supportStatus is required");
        }
        try {
            return CapabilitySupportStatus.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Unknown supportStatus: " + raw);
        }
    }

    private static CapabilityRetrievalMethod parseRetrieval(String raw, WearableDevice device) {
        if (raw == null || raw.isBlank()) {
            return device.getProvider() == WearableProvider.FITPRO
                    ? CapabilityRetrievalMethod.VENDOR_PROTOCOL
                    : CapabilityRetrievalMethod.MANUAL_ENTRY;
        }
        try {
            return CapabilityRetrievalMethod.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Unknown retrievalMethod: " + raw);
        }
    }
}
