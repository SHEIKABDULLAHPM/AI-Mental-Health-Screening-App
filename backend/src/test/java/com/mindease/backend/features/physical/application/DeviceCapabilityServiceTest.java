package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.domain.CapabilitySupportStatus;
import com.mindease.backend.features.physical.domain.DeviceCapability;
import com.mindease.backend.features.physical.domain.DeviceCapabilityRepository;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableProvider;
import com.mindease.backend.features.physical.dto.DeviceCapabilityDtos;

/**
 * The capability registry is the honesty boundary of the whole dashboard: a
 * client may report observations, but only an operational on-device validation
 * can mark a metric as verified.
 */
@ExtendWith(MockitoExtension.class)
class DeviceCapabilityServiceTest {

    private static final String USER = "user-a";
    private static final String DEVICE = "device-1";

    @Mock
    private DeviceCapabilityRepository capabilities;
    @Mock
    private WearableDeviceService devices;

    private final Map<String, DeviceCapability> store = new LinkedHashMap<>();
    private DeviceCapabilityService service;
    private WearableDevice device;

    @BeforeEach
    void setUp() {
        store.clear();
        service = new DeviceCapabilityService(capabilities, devices, new CapabilityCatalog());

        device = new WearableDevice();
        device.setId(DEVICE);
        device.setUserId(USER);
        device.setProvider(WearableProvider.FITPRO);
        device.setModel("Watch 8");
        device.setFirmwareVersion("V15183");
        device.setCapabilities(List.of("STEPS", "SLEEP", "HEART_RATE"));

        lenient().when(devices.requireOwned(USER, DEVICE)).thenReturn(device);
        lenient().when(capabilities.save(any(DeviceCapability.class))).thenAnswer(invocation -> {
            DeviceCapability row = invocation.getArgument(0);
            if (row.getId() == null) {
                row.setId("cap-" + (store.size() + 1));
            }
            store.put(row.getId(), row);
            return row;
        });
        lenient().when(capabilities.findByUserIdAndDeviceIdOrderByMetricAsc(
                        anyString(), anyString()))
                .thenAnswer(invocation -> store.values().stream()
                        .filter(row -> USER.equals(row.getUserId())
                                && DEVICE.equals(row.getDeviceId()))
                        .sorted(Comparator.comparing(DeviceCapability::getMetric))
                        .toList());
        lenient().when(capabilities.findByUserIdAndDeviceIdAndMetric(
                        anyString(), anyString(), anyString()))
                .thenAnswer(invocation -> store.values().stream()
                        .filter(row -> invocation.getArgument(2, String.class)
                                .equals(row.getMetric()))
                        .findFirst());
    }

    private DeviceCapabilityDtos.CapabilityInput input(String metric, String status) {
        return new DeviceCapabilityDtos.CapabilityInput(metric, status, null, null);
    }

    @Test
    void report_cannotSelfCertifyVerification() {
        var response = service.report(USER, DEVICE,
                new DeviceCapabilityDtos.CapabilityReportRequest(
                        List.of(input("SPO2", "SUPPORTED_VERIFIED"))));

        var spo2 = response.capabilities().stream()
                .filter(item -> "SPO2".equals(item.metric())).findFirst().orElseThrow();
        assertThat(spo2.supportStatus()).isEqualTo("SUPPORTED_UNVERIFIED");
        assertThat(spo2.verificationStatus()).isEqualTo("UNVERIFIED");
        assertThat(response.notes())
                .anyMatch(note -> note.contains("cannot self-certify"));
    }

    @Test
    void report_cannotPromoteMetricsTheProviderCannotMeasure() {
        var response = service.report(USER, DEVICE,
                new DeviceCapabilityDtos.CapabilityReportRequest(
                        List.of(input("BODY_FAT", "SUPPORTED_VERIFIED"),
                                input("GPS_ROUTE", "SUPPORTED_UNVERIFIED"),
                                input("STEPS", "SUPPORTED_VERIFIED"))));

        var bodyFat = response.capabilities().stream()
                .filter(item -> "BODY_FAT".equals(item.metric())).findFirst().orElseThrow();
        var gps = response.capabilities().stream()
                .filter(item -> "GPS_ROUTE".equals(item.metric())).findFirst().orElseThrow();
        var steps = response.capabilities().stream()
                .filter(item -> "STEPS".equals(item.metric())).findFirst().orElseThrow();

        assertThat(bodyFat.supportStatus()).isEqualTo("UNSUPPORTED");
        assertThat(bodyFat.retrievalMethod()).isEqualTo("NONE");
        assertThat(bodyFat.limitations()).containsIgnoringCase("No verified");
        assertThat(gps.supportStatus()).isEqualTo("UNSUPPORTED");
        assertThat(gps.retrievalMethod()).isEqualTo("NONE");
        assertThat(gps.limitations()).containsIgnoringCase("no route data");
        // A metric the provider can expose is still accepted, but unverified.
        assertThat(steps.supportStatus()).isEqualTo("SUPPORTED_UNVERIFIED");
    }

    @Test
    void report_rejectsUnknownCapability() {
        assertThatThrownBy(() -> service.report(USER, DEVICE,
                new DeviceCapabilityDtos.CapabilityReportRequest(
                        List.of(input("TELEPORTATION", "SUPPORTED_UNVERIFIED")))))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);
    }

    @Test
    void report_rejectsUnknownSupportStatus() {
        assertThatThrownBy(() -> service.report(USER, DEVICE,
                new DeviceCapabilityDtos.CapabilityReportRequest(
                        List.of(input("SPO2", "PROBABLY")))))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);
    }

    @Test
    void list_seedsEveryCatalogEntryWithoutDuplicatingMetrics() {
        var first = service.list(USER, DEVICE);
        var second = service.list(USER, DEVICE);

        assertThat(first.capabilities()).hasSize(new CapabilityCatalog().all().size());
        assertThat(first.capabilities()).extracting(DeviceCapabilityDtos.CapabilityResponse::metric)
                .doesNotHaveDuplicates();
        assertThat(second.capabilities()).hasSameSizeAs(first.capabilities());
        assertThat(store).hasSize(first.capabilities().size());
    }

    @Test
    void list_marksFitProUnsupportedMetricsExplicitly() {
        var response = service.list(USER, DEVICE);

        var gps = response.capabilities().stream()
                .filter(item -> "GPS_ROUTE".equals(item.metric())).findFirst().orElseThrow();
        var bodyFat = response.capabilities().stream()
                .filter(item -> "BODY_FAT".equals(item.metric())).findFirst().orElseThrow();

        assertThat(gps.supportStatus()).isEqualTo("UNSUPPORTED");
        assertThat(gps.limitations()).containsIgnoringCase("no route data");
        assertThat(bodyFat.supportStatus()).isEqualTo("UNSUPPORTED");
        assertThat(bodyFat.limitations()).containsIgnoringCase("No verified");
    }

    @Test
    void list_neverClaimsVerificationFromTheSeed() {
        var response = service.list(USER, DEVICE);

        assertThat(response.capabilities())
                .noneMatch(item -> "SUPPORTED_VERIFIED".equals(item.supportStatus()));
        assertThat(response.notes())
                .anyMatch(note -> note.contains("No capability has been verified"));
    }

    @Test
    void supportedMetrics_countsOnlySupportedStatuses() {
        DeviceCapability verified = new DeviceCapability();
        verified.setId("c1");
        verified.setUserId(USER);
        verified.setDeviceId(DEVICE);
        verified.setMetric("STEPS");
        verified.setSupportStatus(CapabilitySupportStatus.SUPPORTED_VERIFIED);
        DeviceCapability reported = new DeviceCapability();
        reported.setId("c2");
        reported.setUserId(USER);
        reported.setDeviceId(DEVICE);
        reported.setMetric("SLEEP");
        reported.setSupportStatus(CapabilitySupportStatus.SUPPORTED_UNVERIFIED);
        DeviceCapability unsupported = new DeviceCapability();
        unsupported.setId("c3");
        unsupported.setUserId(USER);
        unsupported.setDeviceId(DEVICE);
        unsupported.setMetric("GPS_ROUTE");
        unsupported.setSupportStatus(CapabilitySupportStatus.UNSUPPORTED);
        store.put("c1", verified);
        store.put("c2", reported);
        store.put("c3", unsupported);

        assertThat(service.supportedMetrics(USER, DEVICE))
                .containsExactlyInAnyOrder("STEPS", "SLEEP");
    }

    @Test
    void list_seedsProtocolMetricsAsSupportedUnverifiedNotUnknown() {
        var response = service.list(USER, DEVICE);

        var steps = response.capabilities().stream()
                .filter(item -> "STEPS".equals(item.metric())).findFirst().orElseThrow();
        var sleep = response.capabilities().stream()
                .filter(item -> "SLEEP".equals(item.metric())).findFirst().orElseThrow();
        var hrv = response.capabilities().stream()
                .filter(item -> "HEART_RATE_VARIABILITY".equals(item.metric())).findFirst().orElseThrow();

        assertThat(steps.supportStatus()).isEqualTo("SUPPORTED_UNVERIFIED");
        assertThat(steps.retrievalMethod()).isEqualTo("VENDOR_PROTOCOL");
        assertThat(steps.limitations()).containsIgnoringCase("no value has been received");
        assertThat(sleep.supportStatus()).isEqualTo("SUPPORTED_UNVERIFIED");
        // No verified frame exists for HRV: it must stay explicitly unsupported.
        assertThat(hrv.supportStatus()).isEqualTo("UNSUPPORTED");
    }

    @Test
    void markVerified_promotesFromObservedRecordOnly() {
        service.list(USER, DEVICE);

        service.markVerified(USER, DEVICE, "STEPS",
                "Confirmed by a record measured on this watch.");
        var afterSteps = service.list(USER, DEVICE).capabilities().stream()
                .filter(item -> "STEPS".equals(item.metric())).findFirst().orElseThrow();
        assertThat(afterSteps.supportStatus()).isEqualTo("SUPPORTED_VERIFIED");
        assertThat(afterSteps.verificationStatus()).isEqualTo("VERIFIED_ON_DEVICE");
        assertThat(afterSteps.lastVerifiedAt()).isNotNull();

        // Provider-unsupported metrics can never be promoted.
        service.markVerified(USER, DEVICE, "HEART_RATE_VARIABILITY", null);
        var afterHrv = service.list(USER, DEVICE).capabilities().stream()
                .filter(item -> "HEART_RATE_VARIABILITY".equals(item.metric()))
                .findFirst().orElseThrow();
        assertThat(afterHrv.supportStatus()).isEqualTo("UNSUPPORTED");
    }

    @Test
    void report_cannotDowngradeAVerifiedCapability() {
        service.list(USER, DEVICE);
        service.markVerified(USER, DEVICE, "STEPS", null);

        var response = service.report(USER, DEVICE,
                new DeviceCapabilityDtos.CapabilityReportRequest(
                        List.of(input("STEPS", "SUPPORTED_UNVERIFIED"))));

        var steps = response.capabilities().stream()
                .filter(item -> "STEPS".equals(item.metric())).findFirst().orElseThrow();
        assertThat(steps.supportStatus()).isEqualTo("SUPPORTED_VERIFIED");
        assertThat(steps.limitations()).containsIgnoringCase("Confirmed by a record");
    }

    @Test
    void crossUserAccess_isNotFound() {
        when(devices.requireOwned(USER, "someone-elses-device"))
                .thenThrow(new ApiException(ErrorCode.NOT_FOUND, "Device not found"));

        assertThatThrownBy(() -> service.list(USER, "someone-elses-device"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }
}
