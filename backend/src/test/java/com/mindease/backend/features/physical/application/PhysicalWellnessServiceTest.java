package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.ExerciseSession;
import com.mindease.backend.features.physical.domain.ExerciseSessionRepository;
import com.mindease.backend.features.physical.domain.HealthMetricType;
import com.mindease.backend.features.physical.domain.HealthReading;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.domain.SyncSession;
import com.mindease.backend.features.physical.domain.SyncSessionRepository;
import com.mindease.backend.features.physical.domain.SyncStatus;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableDeviceRepository;
import com.mindease.backend.features.physical.domain.WearableProvider;
import com.mindease.backend.features.physical.dto.ActivityHistoryResponse;
import com.mindease.backend.features.physical.dto.HeartRateResponse;

/**
 * Dashboard read contract: no device → nothing supported; supported-but-
 * missing data → null (never a fabricated zero); explicit capability lists
 * are honoured.
 */
@ExtendWith(MockitoExtension.class)
class PhysicalWellnessServiceTest {

    private static final String USER = "user-a";

    @Mock
    private WearableDeviceRepository devices;
    @Mock
    private HealthReadingRepository readings;
    @Mock
    private DailyActivityRepository dailyActivity;
    @Mock
    private SleepSessionRepository sleepSessions;
    @Mock
    private ExerciseSessionRepository exerciseSessions;
    @Mock
    private SyncSessionRepository syncSessions;
    @Mock
    private DeviceCapabilityService capabilities;

    private PhysicalWellnessService service;

    @BeforeEach
    void setUp() {
        service = new PhysicalWellnessService(devices, readings, dailyActivity, sleepSessions,
                exerciseSessions, syncSessions, new PhysicalAggregationService(), capabilities);
    }

    private WearableDevice deviceWith(List<String> capabilities) {
        WearableDevice device = new WearableDevice();
        device.setId("device-1");
        device.setUserId(USER);
        device.setProvider(WearableProvider.FITPRO);
        device.setModel("Watch 8");
        device.setFirmwareVersion("V15183");
        device.setConnectionStatus(ConnectionStatus.CONNECTED);
        device.setBatteryLevel(82);
        device.setCapabilities(capabilities);
        return device;
    }

    @Test
    void today_withoutDevice_everythingUnsupported() {
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER)).thenReturn(List.of());
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.empty());
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        when(syncSessions.findFirstByUserIdOrderByStartedAtDesc(USER)).thenReturn(Optional.empty());

        var today = service.today(USER);

        assertThat(today.device()).isNull();
        assertThat(today.steps().supported()).isFalse();
        assertThat(today.steps().value()).isNull();
        assertThat(today.heartRate().supported()).isFalse();
        assertThat(today.sleep().supported()).isFalse();
        assertThat(today.exercise().supported()).isFalse();
    }

    @Test
    void today_capabilityListCanMarkMetricUnavailable() {
        // Device reports only STEPS: heart rate must be explicitly unsupported.
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("STEPS"))));
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.empty());
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        when(syncSessions.findFirstByUserIdOrderByStartedAtDesc(USER)).thenReturn(Optional.empty());

        var today = service.today(USER);

        assertThat(today.steps().supported()).isTrue();
        assertThat(today.steps().value()).isNull(); // supported, but no data yet
        assertThat(today.heartRate().supported()).isFalse();
        assertThat(today.sleep().supported()).isFalse();
    }

    @Test
    void today_genuineZeroSteps_isShownAsZero() {
        DailyActivity activity = new DailyActivity();
        activity.setDate(LocalDate.now());
        activity.setSteps(0);
        activity.setUpdatedAt(Instant.now());
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("STEPS", "DISTANCE", "CALORIES"))));
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.of(activity));
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.empty());
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        when(syncSessions.findFirstByUserIdOrderByStartedAtDesc(USER)).thenReturn(Optional.empty());

        var today = service.today(USER);

        assertThat(today.steps().supported()).isTrue();
        assertThat(today.steps().value()).isNotNull();
        assertThat(today.steps().value()).isEqualTo(0d); // real0 ≠ "no data"
    }

    @Test
    void today_activityValues_areReturnedInCanonicalUnits() {
        DailyActivity activity = new DailyActivity();
        activity.setDate(LocalDate.now());
        activity.setSteps(6842);
        activity.setDistanceMeters(4800d);
        activity.setCaloriesKcal(1840d);
        activity.setUpdatedAt(Instant.now());
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of())));
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.of(activity));
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.empty());
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        when(syncSessions.findFirstByUserIdOrderByStartedAtDesc(USER)).thenReturn(Optional.empty());
        when(readings.findByUserIdAndDateAndMetricTypeOrderByTimestampAsc(any(), any(), any()))
                .thenReturn(List.of());

        var today = service.today(USER);

        assertThat(today.steps().value()).isEqualTo(6842d);
        assertThat(today.steps().unit()).isEqualTo("steps");
        assertThat(today.distance().value()).isEqualTo(4800d);
        assertThat(today.distance().unit()).isEqualTo("m");
        assertThat(today.calories().value()).isEqualTo(1840d);
        assertThat(today.device().batteryLevel()).isEqualTo(82);
        assertThat(today.device().firmwareVersion()).isEqualTo("V15183");
    }

    @Test
    void today_heartRate_latestAndAverageComputed() {
        HealthReading first = hr(Instant.now().minusSeconds(7200), 68);
        HealthReading second = hr(Instant.now().minusSeconds(3600), 76);
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("HEART_RATE"))));
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.empty());
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        when(syncSessions.findFirstByUserIdOrderByStartedAtDesc(USER)).thenReturn(Optional.empty());
        when(readings.findByUserIdAndDateAndMetricTypeOrderByTimestampAsc(any(), any(), any()))
                .thenReturn(List.of(first, second));

        var today = service.today(USER);

        assertThat(today.heartRate().latest()).isEqualTo(76d);
        assertThat(today.heartRate().averageToday()).isEqualTo(72d);
        assertThat(today.heartRate().resting()).isNull(); // never fabricated
        assertThat(today.heartRate().unit()).isEqualTo("bpm");
    }

    @Test
    void today_heartRate_withReadingButStaleCapabilities_isStillShown() {
        // A live measurement can exist even though the history snapshot that
        // seeded capabilities returned no heart-rate frames. Measured data
        // must not be hidden behind a stale capability list.
        HealthReading reading = hr(Instant.now().minusSeconds(300), 78);
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("STEPS"))));
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.empty());
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        when(syncSessions.findFirstByUserIdOrderByStartedAtDesc(USER)).thenReturn(Optional.empty());
        when(readings.findByUserIdAndDateAndMetricTypeOrderByTimestampAsc(any(), any(), any()))
                .thenReturn(List.of(reading));

        var today = service.today(USER);

        assertThat(today.heartRate().supported()).isTrue();
        assertThat(today.heartRate().latest()).isEqualTo(78d);
        assertThat(today.heartRate().updatedAt()).isEqualTo(reading.getTimestamp());
    }

    @Test
    void today_sleepBlock_reflectsLatestSession() {
        SleepSession session = new SleepSession();
        session.setStartTime(Instant.now().minusSeconds(9 * 3600));
        session.setEndTime(Instant.now().minusSeconds(2 * 3600));
        session.setDurationMillis(7 * 3600_000L);
        session.setDate(LocalDate.now());
        session.setRecordedAt(Instant.now());
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("SLEEP"))));
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.of(session));
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        when(syncSessions.findFirstByUserIdOrderByStartedAtDesc(USER)).thenReturn(Optional.empty());

        var today = service.today(USER);

        assertThat(today.sleep().supported()).isTrue();
        assertThat(today.sleep().durationMillis()).isEqualTo(7 * 3600_000L);
        assertThat(today.sleep().bedtime()).isEqualTo(session.getStartTime());
        assertThat(today.sleep().wakeTime()).isEqualTo(session.getEndTime());
    }

    @Test
    void activity_withoutData_isUnavailable_notZero() {
        when(dailyActivity.findByUserIdAndDateBetweenOrderByDateDesc(any(), any(), any()))
                .thenReturn(List.of());

        var history = service.activity(USER, 7);

        assertThat(history.available()).isFalse();
        assertThat(history.days()).isEmpty();
    }

    @Test
    void heartRate_withReadings_hasPointsAndLatest() {
        HealthReading reading = hr(Instant.now().minusSeconds(300), 72);
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("HEART_RATE"))));
        when(readings.findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                any(), any(), any(), any())).thenReturn(List.of(reading));

        HeartRateResponse response = service.heartRate(USER, 24);

        assertThat(response.supported()).isTrue();
        assertThat(response.available()).isTrue();
        assertThat(response.latest()).isEqualTo(72d);
        assertThat(response.readings()).hasSize(1);
    }

    @Test
    void heartRate_deviceWithoutCapability_isUnsupported() {
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("STEPS"))));

        HeartRateResponse response = service.heartRate(USER, 24);

        assertThat(response.supported()).isFalse();
        assertThat(response.available()).isFalse();
    }

    @Test
    void heartRate_withReadingButStaleCapabilities_isStillReturned() {
        HealthReading reading = hr(Instant.now().minusSeconds(120), 78);
        when(devices.findByUserIdOrderByUpdatedAtDesc(USER))
                .thenReturn(List.of(deviceWith(List.of("STEPS"))));
        when(readings.findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                any(), any(), any(), any())).thenReturn(List.of(reading));

        HeartRateResponse response = service.heartRate(USER, 24);

        assertThat(response.supported()).isTrue();
        assertThat(response.available()).isTrue();
        assertThat(response.latest()).isEqualTo(78d);
        assertThat(response.readings()).hasSize(1);
    }

    private static HealthReading hr(Instant timestamp, double value) {
        HealthReading reading = new HealthReading();
        reading.setMetricType(HealthMetricType.HEART_RATE);
        reading.setValue(value);
        reading.setUnit("bpm");
        reading.setTimestamp(timestamp);
        return reading;
    }
}
