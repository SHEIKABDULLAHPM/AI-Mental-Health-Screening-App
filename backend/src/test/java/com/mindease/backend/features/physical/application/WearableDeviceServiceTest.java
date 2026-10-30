package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DuplicateKeyException;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableDeviceRepository;
import com.mindease.backend.features.physical.domain.WearableProvider;
import com.mindease.backend.features.physical.dto.CreateDeviceRequest;
import com.mindease.backend.features.physical.dto.DeviceStatusRequest;

/**
 * Device registration/lifecycle: idempotent registration, ownership isolation
 * and status validation.
 */
@ExtendWith(MockitoExtension.class)
class WearableDeviceServiceTest {

    private static final String USER_A = "user-a";
    private static final String USER_B = "user-b";
    private static final String DEVICE_ID = "device-1";

    @Mock
    private WearableDeviceRepository devices;

    private WearableDeviceService service;

    @BeforeEach
    void setUp() {
        service = new WearableDeviceService(devices, new HealthDataValidator());
    }

    private CreateDeviceRequest request(Integer battery) {
        return new CreateDeviceRequest("FITPRO", "AA:BB:CC:DD:EE:FF", "FitPro", "Watch 8",
                "V15183", List.of("steps", "HEART_RATE", "sleep"), battery);
    }

    @Test
    void register_newDevice_isCreated_withAuthenticatedUser() {
        when(devices.findByUserIdAndDeviceIdentifier(USER_A, "AA:BB:CC:DD:EE:FF"))
                .thenReturn(Optional.empty());
        when(devices.save(any())).thenAnswer(inv -> {
            WearableDevice d = inv.getArgument(0);
            d.setId(DEVICE_ID);
            return d;
        });

        var response = service.register(USER_A, request(82));

        ArgumentCaptor<WearableDevice> captor = ArgumentCaptor.forClass(WearableDevice.class);
        verify(devices).save(captor.capture());
        assertThat(captor.getValue().getUserId()).isEqualTo(USER_A);
        assertThat(captor.getValue().getProvider()).isEqualTo(WearableProvider.FITPRO);
        assertThat(response.firmwareVersion()).isEqualTo("V15183");
        assertThat(response.batteryLevel()).isEqualTo(82);
        // Capabilities are normalized to upper-case identifiers.
        assertThat(response.capabilities()).containsExactly("STEPS", "HEART_RATE", "SLEEP");
    }

    @Test
    void register_sameDeviceTwice_updatesInsteadOfDuplicating() {
        WearableDevice existing = new WearableDevice();
        existing.setId(DEVICE_ID);
        existing.setUserId(USER_A);
        existing.setDeviceIdentifier("AA:BB:CC:DD:EE:FF");
        existing.setProvider(WearableProvider.FITPRO);
        when(devices.findByUserIdAndDeviceIdentifier(USER_A, "AA:BB:CC:DD:EE:FF"))
                .thenReturn(Optional.of(existing));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.register(USER_A, request(70));

        verify(devices, never()).save(argThatNewDevice());
        verify(devices).save(existing);
        assertThat(existing.getBatteryLevel()).isEqualTo(70);
    }

    @Test
    void register_concurrentDuplicate_fallsBackToReloadedRecord() {
        when(devices.findByUserIdAndDeviceIdentifier(USER_A, "AA:BB:CC:DD:EE:FF"))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(reloaded()));
        when(devices.save(any())).thenThrow(new DuplicateKeyException("uq_user_device"));

        var response = service.register(USER_A, request(50));

        assertThat(response.id()).isEqualTo(DEVICE_ID);
    }

    @Test
    void register_invalidBattery_isRejected() {
        assertThatThrownBy(() -> service.register(USER_A, request(150)))
                .isInstanceOf(ApiException.class);
        verify(devices, never()).save(any());
    }

    @Test
    void get_anotherUsersDevice_isNotFound() {
        when(devices.findByIdAndUserId(DEVICE_ID, USER_B)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get(USER_B, DEVICE_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).getStatus().value())
                        .isEqualTo(404));
    }

    @Test
    void list_isScopedToAuthenticatedUser() {
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER_A)).thenReturn(List.of(reloaded()));

        var list = service.list(USER_A);

        assertThat(list).hasSize(1);
        verify(devices, never()).findAll();
    }

    @Test
    void updateStatus_batteryAndConnection_areApplied() {
        WearableDevice device = reloaded();
        when(devices.findByIdAndUserId(DEVICE_ID, USER_A)).thenReturn(Optional.of(device));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        var response = service.updateStatus(USER_A, DEVICE_ID,
                new DeviceStatusRequest(64, true, ConnectionStatus.CONNECTED, "V15183",
                        Instant.now()));

        assertThat(response.batteryLevel()).isEqualTo(64);
        assertThat(response.charging()).isTrue();
        assertThat(device.getLastConnectedAt()).isNotNull();
    }

    @Test
    void updateStatus_invalidBattery_isRejected() {
        WearableDevice device = reloaded();
        when(devices.findByIdAndUserId(DEVICE_ID, USER_A)).thenReturn(Optional.of(device));

        assertThatThrownBy(() -> service.updateStatus(USER_A, DEVICE_ID,
                new DeviceStatusRequest(-5, null, null, null, null)))
                .isInstanceOf(ApiException.class);
        verify(devices, never()).save(any());
    }

    @Test
    void remove_anotherUsersDevice_isNotFound_andNothingDeleted() {
        when(devices.findByIdAndUserId(DEVICE_ID, USER_B)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.remove(USER_B, DEVICE_ID))
                .isInstanceOf(ApiException.class);
        verify(devices, never()).delete(any());
    }

    private WearableDevice reloaded() {
        WearableDevice device = new WearableDevice();
        device.setId(DEVICE_ID);
        device.setUserId(USER_A);
        device.setDeviceIdentifier("AA:BB:CC:DD:EE:FF");
        device.setProvider(WearableProvider.FITPRO);
        return device;
    }

    private WearableDevice argThatNewDevice() {
        return org.mockito.ArgumentMatchers.argThat(d -> d.getId() == null);
    }
}
