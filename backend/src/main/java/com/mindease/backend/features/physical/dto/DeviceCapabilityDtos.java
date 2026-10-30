package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.util.List;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Device capability registry contract.
 *
 * <p>Clients may report what they observed during a connection, but the server
 * never lets a client mark a capability as hardware-verified: verification is
 * an operational decision made after a documented on-device validation.</p>
 */
public final class DeviceCapabilityDtos {

    private DeviceCapabilityDtos() {
    }

    public record CapabilityInput(
            @NotBlank String metric,
            @NotBlank String supportStatus,
            String retrievalMethod,
            @Size(max = 300) String limitations) {
    }

    public record CapabilityReportRequest(List<CapabilityInput> capabilities) {
    }

    public record CapabilityResponse(
            String metric,
            String label,
            String unit,
            String supportStatus,
            String retrievalMethod,
            String verificationStatus,
            String limitations,
            Instant lastVerifiedAt,
            Instant updatedAt) {
    }

    public record CapabilityListResponse(
            String deviceId,
            String deviceModel,
            String firmwareVersion,
            List<CapabilityResponse> capabilities,
            List<String> notes) {
    }
}
