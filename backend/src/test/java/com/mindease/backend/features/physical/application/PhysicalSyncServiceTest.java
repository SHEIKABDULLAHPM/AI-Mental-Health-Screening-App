package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
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
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.ExerciseSession;
import com.mindease.backend.features.physical.domain.ExerciseSessionRepository;
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
import com.mindease.backend.features.physical.dto.SyncRequest;
import com.mindease.backend.features.physical.dto.SyncResponse;
import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Synchronization ingest contract: ownership, validation, deduplication,
 * daily merge behaviour and sync session bookkeeping.
 */
@ExtendWith(MockitoExtension.class)
class PhysicalSyncServiceTest {

    private static final String USER_A = "user-a";
    private static final String USER_B = "user-b";
    private static final String DEVICE_ID = "device-1";

    @Mock
    private WearableDeviceRepository devices;
    @Mock
    private WearableDeviceService deviceService;
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

    private PhysicalSyncService service;
    private WearableDevice device;

    @BeforeEach
    void setUp() {
        service = new PhysicalSyncService(devices, deviceService, readings, dailyActivity,
                sleepSessions, exerciseSessions, syncSessions, new HealthDataValidator());
        device = new WearableDevice();
        device.setId(DEVICE_ID);
        device.setUserId(USER_A);
        device.setProvider(WearableProvider.FITPRO);
        device.setConnectionStatus(ConnectionStatus.CONNECTED);
    }

    private SyncRequest req(List<SyncRequest.ReadingInput> readings,
                            List<SyncRequest.DailyActivityInput> daily,
                            List<SyncRequest.SleepInput> sleep,
                            List<SyncRequest.ExerciseInput> exercise,
                            SyncRequest.DeviceStatusInput status) {
        return new SyncRequest("sync-1", DEVICE_ID, status, readings, daily, sleep, exercise, null);
    }

    /** Mirrors the service's zone resolution (UTC when no user timezone is set). */
    private java.time.ZoneId serviceZone() {
        return ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
    }

    @Test
    void sync_deviceOwnedByAnotherUser_throwsNotFound() {
        when(deviceService.requireOwned(USER_B, DEVICE_ID))
                .thenThrow(ApiException.notFound("Wearable device not found"));

        assertThatThrownBy(() -> service.sync(USER_B, req(null, null, null, null, null)))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).getStatus().value())
                        .isEqualTo(404));
        verify(syncSessions, never()).save(any());
    }

    @Test
    void sync_validBatch_isAccepted_andSessionRecorded() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(readings.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        SyncRequest request = req(List.of(reading("STEPS", 6842d, "steps"),
                        reading("HEART_RATE", 72d, "bpm"),
                        reading("DISTANCE", 4.8, "km")), null, null, null, null);

        SyncResponse response = service.sync(USER_A, request);

        assertThat(response.status()).isEqualTo(SyncStatus.SUCCESS);
        assertThat(response.accepted()).isEqualTo(3);
        assertThat(response.rejected()).isZero();
        assertThat(response.rejections()).isEmpty();

        ArgumentCaptor<HealthReading> captor = ArgumentCaptor.forClass(HealthReading.class);
        verify(readings, org.mockito.Mockito.times(3)).save(captor.capture());
        List<HealthReading> saved = captor.getAllValues();
        // Units normalized to canonical: km → m, steps unit → count.
        assertThat(saved.get(0).getUnit()).isEqualTo("count");
        assertThat(saved.get(2).getValue()).isEqualTo(4800d);
        assertThat(saved.get(2).getUnit()).isEqualTo("m");
        assertThat(saved.get(0).getSource()).isEqualTo(WearableProvider.FITPRO);
        assertThat(saved.get(0).getDate()).isNotNull();

        ArgumentCaptor<SyncSession> sessionCaptor = ArgumentCaptor.forClass(SyncSession.class);
        verify(syncSessions).save(sessionCaptor.capture());
        assertThat(sessionCaptor.getValue().getRecordsAccepted()).isEqualTo(3);
        assertThat(sessionCaptor.getValue().getUserId()).isEqualTo(USER_A);
    }

    @Test
    void sync_replayedReading_countsDuplicate_notError() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(readings.save(any())).thenThrow(new DuplicateKeyException("uq_reading"));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        SyncResponse response = service.sync(USER_A, req(List.of(reading("STEPS", 100d, "steps")), null, null, null, null));

        assertThat(response.duplicates()).isEqualTo(1);
        assertThat(response.rejected()).isZero();
        assertThat(response.status()).isEqualTo(SyncStatus.SUCCESS);
    }

    @Test
    void sync_replayedBatchId_isIdempotent_bookkeepingOnly() {
        // A batch that was fully processed before but whose response never
        // reached the client replays verbatim. It must echo the original
        // session instead of storing records again, re-stamping the device,
        // or creating a second audit row.
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        SyncSession stored = new SyncSession();
        stored.setId("sync-1");
        stored.setUserId(USER_A);
        stored.setStatus(SyncStatus.SUCCESS);
        stored.setCompletedAt(Instant.now());
        when(syncSessions.findFirstByUserIdAndClientSyncId(USER_A, "sync-1"))
                .thenReturn(Optional.of(stored));

        SyncResponse response = service.sync(USER_A,
                req(List.of(reading("STEPS", 100d, "steps")), null, null, null, null));

        assertThat(response.syncSessionId()).isEqualTo("sync-1");
        assertThat(response.status()).isEqualTo(SyncStatus.SUCCESS);
        assertThat(response.accepted()).isZero();
        assertThat(response.duplicates()).isEqualTo(1);
        assertThat(response.rejected()).isZero();
        verify(readings, never()).save(any());
        verify(syncSessions, never()).save(any());
        verify(devices, never()).save(any());
    }

    @Test
    void sync_dailyActivityInsertLostUniqueIndexRace_mergesIntoStoredRow() {
        // Two concurrent/replayed syncs can both pass the find-then-save
        // read; the unique index `uq_user_day` rejects the second insert.
        // The service must merge over the winner's row instead of failing
        // the whole legal batch with an HTTP 500.
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        DailyActivity winner = new DailyActivity();
        winner.setSteps(100);
        when(dailyActivity.findByUserIdAndDate(any(), any()))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(winner));
        when(dailyActivity.save(any()))
                .thenThrow(new DuplicateKeyException("uq_user_day"))
                .thenAnswer(inv -> inv.getArgument(0));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        LocalDate today = LocalDate.now(serviceZone());
        SyncResponse response = service.sync(USER_A, req(null, List.of(
                new SyncRequest.DailyActivityInput(today, 6842, 4.8, "km", 1840.0, 42, null)),
                null, null, null));

        assertThat(response.status()).isEqualTo(SyncStatus.SUCCESS);
        assertThat(response.rejected()).isZero();
        assertThat(winner.getSteps()).isEqualTo(6842);
        assertThat(winner.getDistanceMeters()).isEqualTo(4800d);
        assertThat(winner.getCaloriesKcal()).isEqualTo(1840d);
        assertThat(winner.getActiveMinutes()).isEqualTo(42);
    }

    @Test
    void sync_implausibleHeartRate_isRejectedWithReason() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        SyncResponse response = service.sync(USER_A, req(List.of(reading("HEART_RATE", 400d, "bpm"),
                        reading("STEPS", 500d, "steps")), null, null, null, null));

        assertThat(response.rejected()).isEqualTo(1);
        assertThat(response.accepted()).isEqualTo(1);
        assertThat(response.status()).isEqualTo(SyncStatus.PARTIAL);
        SyncResponse.Rejection rejection = response.rejections().get(0);
        assertThat(rejection.category()).isEqualTo("reading");
        assertThat(rejection.index()).isZero();
        assertThat(rejection.reason()).contains("Heart rate");
        verify(readings, org.mockito.Mockito.times(1)).save(any());
    }

    @Test
    void sync_allRecordsInvalid_marksSessionFailed() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        SyncResponse response = service.sync(USER_A, req(List.of(reading("HEART_RATE", 999d, "bpm")), null, null, null, null));

        assertThat(response.status()).isEqualTo(SyncStatus.FAILED);
        assertThat(response.accepted()).isZero();
    }

    @Test
    void sync_dailyTotal_replacesIntervalData() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(dailyActivity.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        LocalDate today = LocalDate.now(serviceZone());
        service.sync(USER_A, req(null, List.of(new SyncRequest.DailyActivityInput(
                        today, 6842, 4.8, "km", 1840.0, 42, null)), null, null, null));

        ArgumentCaptor<DailyActivity> captor = ArgumentCaptor.forClass(DailyActivity.class);
        verify(dailyActivity).save(captor.capture());
        DailyActivity saved = captor.getValue();
        assertThat(saved.getSteps()).isEqualTo(6842);
        assertThat(saved.getDistanceMeters()).isEqualTo(4800d);
        assertThat(saved.getCaloriesKcal()).isEqualTo(1840d);
        assertThat(saved.getActiveMinutes()).isEqualTo(42);
    }

    @Test
    void sync_intervalDelta_addsToStoredDay() {
        // FitPro deletes history after sending once, so the next fetch only
        // carries new chunks. A delta must extend the stored day, never
        // replace it (423 steps stored + 701 new = 1124).
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        DailyActivity existing = new DailyActivity();
        existing.setSteps(423);
        existing.setDistanceMeters(346d);
        existing.setCaloriesKcal(8d);
        existing.setActiveMinutes(10);
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.of(existing));
        when(dailyActivity.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.sync(USER_A, req(null, List.of(new SyncRequest.DailyActivityInput(
                LocalDate.now(serviceZone()), 701, 484d, "m", 14.0, 20,
                "INTERVAL_DELTA")), null, null, null));

        ArgumentCaptor<DailyActivity> captor = ArgumentCaptor.forClass(DailyActivity.class);
        verify(dailyActivity).save(captor.capture());
        DailyActivity saved = captor.getValue();
        assertThat(saved.getSteps()).isEqualTo(1124);
        assertThat(saved.getDistanceMeters()).isEqualTo(830d);
        assertThat(saved.getCaloriesKcal()).isEqualTo(22d);
        assertThat(saved.getActiveMinutes()).isEqualTo(30);
    }

    @Test
    void sync_withoutDailyTotal_sumsIntervalReadings() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(readings.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(dailyActivity.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.sync(USER_A, req(List.of(reading("STEPS", 100d, "steps"),
                        reading("STEPS", 250d, "steps")), null, null, null, null));

        ArgumentCaptor<DailyActivity> captor = ArgumentCaptor.forClass(DailyActivity.class);
        verify(dailyActivity).save(captor.capture());
        assertThat(captor.getValue().getSteps()).isEqualTo(350);
    }

    @Test
    void sync_dayWithNoDataAtAll_staysNull_neverZero() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(dailyActivity.findByUserIdAndDate(any(), any())).thenReturn(Optional.empty());
        when(dailyActivity.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.sync(USER_A, req(null, List.of(new SyncRequest.DailyActivityInput(
                        LocalDate.now(serviceZone()), null, null, null, null, null, null)), null, null, null));

        ArgumentCaptor<DailyActivity> captor = ArgumentCaptor.forClass(DailyActivity.class);
        verify(dailyActivity).save(captor.capture());
        assertThat(captor.getValue().getSteps()).isNull();
        assertThat(captor.getValue().getDistanceMeters()).isNull();
        assertThat(captor.getValue().getCaloriesKcal()).isNull();
    }

    @Test
    void sync_duplicateSleepSession_countsDuplicate() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(sleepSessions.findByUserIdAndDeviceIdAndStartTime(any(), any(), any()))
                .thenReturn(Optional.of(new SleepSession()));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Instant start = Instant.now().minusSeconds(8 * 3600);
        Instant end = Instant.now().minusSeconds(3600);
        SyncResponse response = service.sync(USER_A, req(null, null, List.of(new SyncRequest.SleepInput(start, end, null, null, null, null)), null, null));

        assertThat(response.duplicates()).isEqualTo(1);
        verify(sleepSessions, never()).save(any());
    }

    @Test
    void sync_invalidSleepWindow_isRejected() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Instant now = Instant.now();
        SyncResponse response = service.sync(USER_A, req(null, null, List.of(new SyncRequest.SleepInput(now, now.minusSeconds(600), null, null, null, null)), null, null));

        assertThat(response.rejected()).isEqualTo(1);
        assertThat(response.rejections().get(0).category()).isEqualTo("sleep");
        verify(sleepSessions, never()).save(any());
    }

    @Test
    void sync_implausibleExerciseHeartRate_isRejected() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Instant start = Instant.now().minusSeconds(3600);
        Instant end = Instant.now();
        SyncResponse response = service.sync(USER_A, req(null, null, null, List.of(new SyncRequest.ExerciseInput(
                        "WALKING", start, end, null, null, null, null, 400d, null)), null));

        assertThat(response.rejected()).isEqualTo(1);
        verify(exerciseSessions, never()).save(any());
    }

    @Test
    void sync_updatesDeviceStatus_andLastSyncedAt() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.sync(USER_A, req(null, null, null, null, new SyncRequest.DeviceStatusInput(
                        82, false, "CONNECTED", "V15183")));

        assertThat(device.getBatteryLevel()).isEqualTo(82);
        assertThat(device.getCharging()).isFalse();
        assertThat(device.getFirmwareVersion()).isEqualTo("V15183");
        assertThat(device.getLastSyncedAt()).isNotNull();
        assertThat(device.getLastSeenAt()).isNotNull();
    }

    @Test
    void sync_invalidBattery_neverOverwritesStoredLevel() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));
        device.setBatteryLevel(82);

        service.sync(USER_A, req(null, null, null, null, new SyncRequest.DeviceStatusInput(150, null, null, null)));

        assertThat(device.getBatteryLevel()).isEqualTo(82);
    }

    @Test
    void sync_persistsSourceNativeSleepStages() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(sleepSessions.findByUserIdAndDeviceIdAndStartTime(any(), any(), any()))
                .thenReturn(Optional.empty());
        when(sleepSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Instant start = Instant.now().minusSeconds(8 * 3600);
        Instant end = Instant.now().minusSeconds(3600);
        SyncResponse response = service.sync(USER_A, req(null, null, List.of(
                new SyncRequest.SleepInput(start, end, null,
                        java.util.Map.of("raw_1", 120, "RAW_2", 60),
                        "fitpro_raw", null)), null, null));

        ArgumentCaptor<SleepSession> captor = ArgumentCaptor.forClass(SleepSession.class);
        verify(sleepSessions).save(captor.capture());
        assertThat(response.accepted()).isEqualTo(1);
        assertThat(captor.getValue().getStageMinutes())
                .containsEntry("RAW_1", 120)
                .containsEntry("RAW_2", 60);
        assertThat(captor.getValue().getStageSource()).isEqualTo("FITPRO_RAW");
    }

    @Test
    void sync_rejectsStagesThatExceedTheSession() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Instant start = Instant.now().minusSeconds(3600);
        Instant end = Instant.now();
        SyncResponse response = service.sync(USER_A, req(null, null, List.of(
                new SyncRequest.SleepInput(start, end, null,
                        java.util.Map.of("RAW_1", 240), "FITPRO_RAW", null)), null, null));

        assertThat(response.rejected()).isEqualTo(1);
        assertThat(response.rejections().get(0).reason())
                .containsIgnoringCase("exceed");
        verify(sleepSessions, never()).save(any());
    }

    @Test
    void sync_rejectsInvalidStageLabels() {
        when(deviceService.requireOwned(USER_A, DEVICE_ID)).thenReturn(device);
        when(syncSessions.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(devices.save(any())).thenAnswer(inv -> inv.getArgument(0));

        Instant start = Instant.now().minusSeconds(3600);
        Instant end = Instant.now();
        SyncResponse response = service.sync(USER_A, req(null, null, List.of(
                new SyncRequest.SleepInput(start, end, null,
                        java.util.Map.of("<script>", 10), "FITPRO_RAW", null)), null, null));

        assertThat(response.rejected()).isEqualTo(1);
        verify(sleepSessions, never()).save(any());
    }

    private static SyncRequest.ReadingInput reading(String metricType, double value, String unit) {
        return new SyncRequest.ReadingInput(metricType, value, unit,
                Instant.now().minusSeconds(60), null, null);
    }
}
