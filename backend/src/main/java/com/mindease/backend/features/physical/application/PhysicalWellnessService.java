package com.mindease.backend.features.physical.application;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

import org.springframework.stereotype.Service;

import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
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
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableDeviceRepository;
import com.mindease.backend.features.physical.dto.ActivityHistoryResponse;
import com.mindease.backend.features.physical.dto.ExerciseHistoryResponse;
import com.mindease.backend.features.physical.dto.HeartRateResponse;
import com.mindease.backend.features.physical.dto.PhysicalTodayResponse;
import com.mindease.backend.features.physical.dto.SleepHistoryResponse;
import com.mindease.backend.features.physical.dto.WeeklySummaryResponse;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Read side of the Physical Wellness domain: the dashboard payload and the
 * history endpoints behind it.
 *
 * <p>Support semantics: a metric is {@code supported=false} only when the
 * registered device's capability list says so; supported metrics without data
 * come back with a null value so the UI shows "no data" instead of a fake
 * zero.</p>
 */
@Service
public class PhysicalWellnessService {

    private static final int MAX_HISTORY_DAYS = 90;
    private static final int DEFAULT_HISTORY_DAYS = 14;
    private static final int MAX_HR_POINTS = 288;

    private final WearableDeviceRepository devices;
    private final HealthReadingRepository readings;
    private final DailyActivityRepository dailyActivity;
    private final SleepSessionRepository sleepSessions;
    private final ExerciseSessionRepository exerciseSessions;
    private final SyncSessionRepository syncSessions;
    private final PhysicalAggregationService aggregation;
    private final DeviceCapabilityService capabilities;

    public PhysicalWellnessService(WearableDeviceRepository devices,
                                   HealthReadingRepository readings,
                                   DailyActivityRepository dailyActivity,
                                   SleepSessionRepository sleepSessions,
                                   ExerciseSessionRepository exerciseSessions,
                                   SyncSessionRepository syncSessions,
                                   PhysicalAggregationService aggregation,
                                   DeviceCapabilityService capabilities) {
        this.devices = devices;
        this.readings = readings;
        this.dailyActivity = dailyActivity;
        this.sleepSessions = sleepSessions;
        this.exerciseSessions = exerciseSessions;
        this.syncSessions = syncSessions;
        this.aggregation = aggregation;
        this.capabilities = capabilities;
    }

    public PhysicalTodayResponse today(String userId) {
        ZoneId zone = zone();
        LocalDate date = LocalDate.now(zone);
        Instant dayStart = date.atStartOfDay(zone).toInstant();

        WearableDevice device = devices.findByUserIdOrderByUpdatedAtDesc(userId).stream()
                .findFirst().orElse(null);

        DailyActivity activity = dailyActivity.findByUserIdAndDate(userId, date).orElse(null);
        SleepSession latestSleep = sleepSessions.findFirstByUserIdOrderByStartTimeDesc(userId)
                .orElse(null);
        // Sessions may begin up to the tolerated 5-minute clock skew in the
        // future (HealthDataValidator.MAX_CLOCK_SKEW); bounding the query at
        // Instant.now() silently hid those starts. The day boundary is the
        // correct attribution range.
        List<ExerciseSession> todaySessions = exerciseSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                        userId, dayStart, date.plusDays(1).atStartOfDay(zone).toInstant())
                .stream().toList();

        long exerciseMillis = 0;
        for (ExerciseSession session : todaySessions) {
            if (session.getDurationMillis() != null) {
                exerciseMillis += session.getDurationMillis();
            }
        }

        reconcileVerifiedCapabilities(userId, device);

        PhysicalTodayResponse.HeartRateBlock heartRate = heartRateBlock(userId, device, dayStart, zone);
        SyncSession lastSync = syncSessions.findFirstByUserIdOrderByStartedAtDesc(userId)
                .orElse(null);

        return new PhysicalTodayResponse(
                date,
                deviceBlock(device),
                metricBlock(userId, device, HealthMetricType.STEPS, "steps",
                        activity == null ? null : intOrNull(activity.getSteps()),
                        activity == null ? null : activity.getUpdatedAt()),
                metricBlock(userId, device, HealthMetricType.DISTANCE, "m",
                        activity == null ? null : activity.getDistanceMeters(),
                        activity == null ? null : activity.getUpdatedAt()),
                metricBlock(userId, device, HealthMetricType.CALORIES, "kcal",
                        activity == null ? null : activity.getCaloriesKcal(),
                        activity == null ? null : activity.getUpdatedAt()),
                heartRate,
                sleepBlock(userId, device, latestSleep),
                exerciseBlock(userId, device, todaySessions, exerciseMillis),
                activeMinutesBlock(userId, device, activity),
                readingBlock(userId, device, HealthMetricType.SPO2, "%", date, zone),
                readingBlock(userId, device, HealthMetricType.HEART_RATE_VARIABILITY, "ms",
                        date, zone),
                syncBlock(device, lastSync));
    }

    public ActivityHistoryResponse activity(String userId, Integer daysParam) {
        int days = clampDays(daysParam);
        ZoneId zone = zone();
        LocalDate today = LocalDate.now(zone);
        List<DailyActivity> rows = dailyActivity
                .findByUserIdAndDateBetweenOrderByDateDesc(userId, today.minusDays(days - 1), today);
        if (rows.isEmpty()) {
            return ActivityHistoryResponse.empty();
        }
        List<ActivityHistoryResponse.ActivityDay> mapped = new ArrayList<>();
        for (DailyActivity row : rows) {
            mapped.add(new ActivityHistoryResponse.ActivityDay(
                    row.getDate(), row.getSteps(), row.getDistanceMeters(),
                    row.getCaloriesKcal(), row.getActiveMinutes()));
        }
        return new ActivityHistoryResponse(true, mapped);
    }

    public HeartRateResponse heartRate(String userId, Integer hoursParam) {
        WearableDevice device = devices.findByUserIdOrderByUpdatedAtDesc(userId).stream()
                .findFirst().orElse(null);
        int hours = hoursParam == null ? 24 : Math.min(Math.max(hoursParam, 1), 24 * 14);
        Instant from = Instant.now().minus(Duration.ofHours(hours));
        List<HealthReading> rows = readings
                .findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                        userId, HealthMetricType.HEART_RATE, from, Instant.now());
        // Observed readings win over a stale capability declaration: a live
        // measurement can arrive without the history snapshot that seeded the
        // capability list, and hiding it would look like the watch never
        // measured anything.
        if (rows.isEmpty() && !supports(userId, device, HealthMetricType.HEART_RATE)) {
            return HeartRateResponse.unsupported();
        }
        if (rows.isEmpty()) {
            return HeartRateResponse.noData();
        }
        List<HeartRateResponse.Point> points = new ArrayList<>();
        List<Double> values = new ArrayList<>();
        for (HealthReading row : rows) {
            points.add(new HeartRateResponse.Point(row.getTimestamp(), row.getValue()));
            values.add(row.getValue());
        }
        if (points.size() > MAX_HR_POINTS) {
            points = points.subList(0, MAX_HR_POINTS);
        }
        HealthReading latest = rows.get(0);
        return new HeartRateResponse(true, true, latest.getValue(),
                aggregation.average(values), null, "bpm", latest.getTimestamp(), points);
    }

    public SleepHistoryResponse sleep(String userId, Integer limitParam) {
        int limit = limitParam == null ? 14 : Math.min(Math.max(limitParam, 1), 90);
        ZoneId zone = zone();
        // Wake-day attribution: a session waking on the first requested day
        // starts the previous evening, so the query starts one day earlier.
        Instant from = LocalDate.now(zone).minusDays(limit + 1)
                .atStartOfDay(zone).toInstant();
        List<SleepSession> rows = sleepSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(userId, from, Instant.now());
        if (rows.isEmpty()) {
            return SleepHistoryResponse.empty();
        }
        List<SleepHistoryResponse.Session> mapped = new ArrayList<>();
        for (SleepSession row : rows) {
            mapped.add(new SleepHistoryResponse.Session(row.getDate(), row.getStartTime(),
                    row.getEndTime(), row.getDurationMillis()));
        }
        return new SleepHistoryResponse(true, mapped.get(0), mapped);
    }

    public ExerciseHistoryResponse exercise(String userId, Integer limitParam) {
        int limit = limitParam == null ? 30 : Math.min(Math.max(limitParam, 1), 90);
        ZoneId zone = zone();
        Instant from = LocalDate.now(zone).minusDays(limit).atStartOfDay(zone).toInstant();
        List<ExerciseSession> rows = exerciseSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(userId, from, Instant.now());
        if (rows.isEmpty()) {
            return ExerciseHistoryResponse.empty();
        }
        List<ExerciseHistoryResponse.Session> mapped = new ArrayList<>();
        for (ExerciseSession row : rows) {
            mapped.add(new ExerciseHistoryResponse.Session(row.getDate(), row.getType(),
                    row.getStartTime(), row.getEndTime(), row.getDurationMillis(),
                    row.getDistanceMeters(), row.getCaloriesKcal(),
                    row.getAverageHeartRate(), row.getMaximumHeartRate()));
        }
        return new ExerciseHistoryResponse(true, mapped.get(0), mapped);
    }

    public WeeklySummaryResponse weekly(String userId) {
        ZoneId zone = zone();
        LocalDate today = LocalDate.now(zone);
        List<DailyActivity> rows = dailyActivity.findTop14ByUserIdOrderByDateDesc(userId);
        PhysicalAggregationService.WeeklyActivitySummary activity =
                aggregation.weeklyActivity(rows, today);
        // Sleep is attributed to the wake day, so the overnight session waking
        // on the window's first day (today-6) starts on today-7: query one
        // extra day back and let the wake-day aggregate bound the window, and
        // use the same 7-day period as the activity summary (it previously
        // mixed an 8-day sleep window into a 7-day payload).
        List<SleepSession> sleepRows = sleepSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                        userId, today.minusDays(7).atStartOfDay(zone).toInstant(),
                        today.plusDays(1).atStartOfDay(zone).toInstant());
        PhysicalAggregationService.WeeklySleepSummary sleep =
                aggregation.weeklySleep(sleepRows, today, today.minusDays(6));

        List<ActivityHistoryResponse.ActivityDay> days = new ArrayList<>();
        for (DailyActivity row : rows) {
            if (row.getDate() != null && !row.getDate().isBefore(today.minusDays(6))
                    && !row.getDate().isAfter(today)) {
                days.add(new ActivityHistoryResponse.ActivityDay(row.getDate(), row.getSteps(),
                        row.getDistanceMeters(), row.getCaloriesKcal(), row.getActiveMinutes()));
            }
        }
        days.sort((a, b) -> b.date().compareTo(a.date()));

        return new WeeklySummaryResponse(
                activity.periodStart(),
                activity.periodEnd(),
                activity.daysWithData(),
                activity.totalSteps(),
                activity.averageSteps(),
                activity.totalDistanceMeters(),
                activity.totalCaloriesKcal(),
                activity.bestStepDay(),
                activity.bestStepDate(),
                sleep.sessionsWithData(),
                sleep.averageDurationMillis(),
                days);
    }

    // ──────────────────────────────────────── block builders

    private PhysicalTodayResponse.DeviceBlock deviceBlock(WearableDevice device) {
        if (device == null) {
            return null;
        }
        return new PhysicalTodayResponse.DeviceBlock(
                device.getId(),
                device.getProvider(),
                device.getManufacturer(),
                device.getModel(),
                device.getFirmwareVersion(),
                device.getConnectionStatus() == null ? ConnectionStatus.UNKNOWN : device.getConnectionStatus(),
                device.getBatteryLevel(),
                device.getCharging(),
                device.getLastSyncedAt());
    }

    private PhysicalTodayResponse.MetricBlock metricBlock(String userId, WearableDevice device,
                                                          HealthMetricType type, String unit,
                                                          Double value, Instant updatedAt) {
        if (!supports(userId, device, type)) {
            return PhysicalTodayResponse.MetricBlock.unsupported(unit);
        }
        if (value == null) {
            return PhysicalTodayResponse.MetricBlock.noData(unit);
        }
        return new PhysicalTodayResponse.MetricBlock(true, value, unit, updatedAt);
    }

    private PhysicalTodayResponse.HeartRateBlock heartRateBlock(String userId, WearableDevice device,
                                                                Instant dayStart, ZoneId zone) {
        List<HealthReading> todayRows = readings
                .findByUserIdAndDateAndMetricTypeOrderByTimestampAsc(
                        userId, dayStart.atZone(zone).toLocalDate(), HealthMetricType.HEART_RATE);
        // A real reading is stronger evidence than a stale capability list:
        // live measurements can exist even when the history snapshot that
        // seeded the device capabilities returned no heart-rate frames. Never
        // hide measured data as "unsupported".
        if (!supports(userId, device, HealthMetricType.HEART_RATE) && todayRows.isEmpty()) {
            return new PhysicalTodayResponse.HeartRateBlock(false, null, null, null, "bpm", null);
        }
        Double latest = null;
        Instant updatedAt = null;
        Double average = null;
        if (!todayRows.isEmpty()) {
            HealthReading last = todayRows.get(todayRows.size() - 1);
            latest = last.getValue();
            updatedAt = last.getTimestamp();
            List<Double> values = new ArrayList<>();
            for (HealthReading row : todayRows) {
                values.add(row.getValue());
            }
            average = aggregation.average(values);
        }
        Double resting = latestValue(userId, HealthMetricType.RESTING_HEART_RATE);
        return new PhysicalTodayResponse.HeartRateBlock(true, latest, average, resting, "bpm",
                updatedAt);
    }

    private PhysicalTodayResponse.MetricBlock activeMinutesBlock(String userId,
                                                                 WearableDevice device,
                                                                 DailyActivity activity) {
        Integer active = activity == null ? null : activity.getActiveMinutes();
        boolean declared = supports(userId, device, HealthMetricType.ACTIVE_MINUTES);
        if (!declared && active == null) {
            return PhysicalTodayResponse.MetricBlock.unsupported("min");
        }
        return active == null
                ? PhysicalTodayResponse.MetricBlock.noData("min")
                : new PhysicalTodayResponse.MetricBlock(true, active.doubleValue(), "min",
                        activity.getUpdatedAt());
    }

    /**
     * Point-metric block (SpO2, HRV) that is supported only when the device
     * explicitly declares the capability or a real reading already exists.
     * Silence must never be presented as "supported but empty" for metrics the
     * hardware cannot measure.
     */
    private PhysicalTodayResponse.MetricBlock readingBlock(String userId, WearableDevice device,
                                                           HealthMetricType type, String unit,
                                                           LocalDate date, ZoneId zone) {
        List<HealthReading> rows = readings
                .findByUserIdAndDateAndMetricTypeOrderByTimestampAsc(userId, date, type);
        boolean declared = supports(userId, device, type);
        if (!declared && rows.isEmpty()) {
            return PhysicalTodayResponse.MetricBlock.unsupported(unit);
        }
        if (rows.isEmpty()) {
            return PhysicalTodayResponse.MetricBlock.noData(unit);
        }
        HealthReading latest = rows.get(rows.size() - 1);
        return new PhysicalTodayResponse.MetricBlock(true, latest.getValue(), unit,
                latest.getTimestamp());
    }

    private Double latestValue(String userId, HealthMetricType type) {
        return readings.findFirstByUserIdAndMetricTypeOrderByTimestampDesc(userId, type)
                .map(HealthReading::getValue)
                .orElse(null);
    }

    private PhysicalTodayResponse.SleepBlock sleepBlock(String userId, WearableDevice device,
                                                         SleepSession latest) {
        if (!supports(userId, device, HealthMetricType.SLEEP)) {
            return new PhysicalTodayResponse.SleepBlock(false, null, null, null, null, null,
                    null, null);
        }
        if (latest == null) {
            return new PhysicalTodayResponse.SleepBlock(true, null, null, null, null, null,
                    null, null);
        }
        return new PhysicalTodayResponse.SleepBlock(true, latest.getDurationMillis(),
                latest.getStartTime(), latest.getEndTime(), latest.getDate(),
                latest.getRecordedAt(), latest.getStageMinutes(), latest.getStageSource());
    }

    private PhysicalTodayResponse.ExerciseBlock exerciseBlock(String userId,
                                                              WearableDevice device,
                                                              List<ExerciseSession> todaySessions,
                                                              long totalMillis) {
        if (!supports(userId, device, HealthMetricType.EXERCISE)) {
            return new PhysicalTodayResponse.ExerciseBlock(false, null, 0, null);
        }
        if (todaySessions.isEmpty()) {
            return new PhysicalTodayResponse.ExerciseBlock(true, null, 0, null);
        }
        Instant latest = todaySessions.get(0).getRecordedAt();
        return new PhysicalTodayResponse.ExerciseBlock(true, totalMillis,
                todaySessions.size(), latest);
    }

    private PhysicalTodayResponse.SyncBlock syncBlock(WearableDevice device, SyncSession lastSync) {
        Instant lastSyncedAt = device != null ? device.getLastSyncedAt() : null;
        if (lastSync == null) {
            return new PhysicalTodayResponse.SyncBlock(lastSyncedAt, null, null, null);
        }
        return new PhysicalTodayResponse.SyncBlock(
                lastSyncedAt != null ? lastSyncedAt : lastSync.getCompletedAt(),
                lastSync.getStartedAt(),
                lastSync.getStatus(),
                lastSync.getError());
    }

    /**
     * Capability resolution. The server-side registry (protocol knowledge plus
     * observed records) is authoritative; the device's legacy capability list
     * is only a fallback for providers that never report one. An explicit
     * {@code UNSUPPORTED} registry row is respected, so HRV/SpO2 are not
     * presented as "supported but empty".
     */
    private boolean supports(String userId, WearableDevice device, HealthMetricType type) {
        if (device == null) {
            return false;
        }
        if (capabilities.supportedMetrics(userId, device).contains(type.name())) {
            return true;
        }
        List<String> declared = device.getCapabilities();
        if (declared == null || declared.isEmpty()) {
            return true;
        }
        return declared.contains(type.name());
    }

    /**
     * Promotes capabilities that have real evidence on this watch. Only the
     * server performs this: a stored device-measured reading or a synced
     * daily/sleep row is proof the metric works on this unit. Manual entries
     * (weight, hydration) are never promoted here.
     */
    private void reconcileVerifiedCapabilities(String userId, WearableDevice device) {
        if (device == null) {
            return;
        }
        String deviceId = device.getId();
        if (device.getBatteryLevel() != null) {
            capabilities.markVerified(userId, deviceId, "BATTERY_LEVEL",
                    "Read from the standard battery service on this watch.");
        }
        if (device.getFirmwareVersion() != null) {
            capabilities.markVerified(userId, deviceId, "FIRMWARE_INFO",
                    "Read from the standard device-information service on this watch.");
        }
        if (device.getModel() != null) {
            capabilities.markVerified(userId, deviceId, "DEVICE_MODEL",
                    "Read from the standard device-information service on this watch.");
        }
        markReadingVerified(userId, deviceId, HealthMetricType.HEART_RATE, "HEART_RATE");
        markReadingVerified(userId, deviceId, HealthMetricType.SPO2, "SPO2");
        markReadingVerified(userId, deviceId, HealthMetricType.HEART_RATE_VARIABILITY,
                "HEART_RATE_VARIABILITY");

        dailyActivity.findTop14ByUserIdOrderByDateDesc(userId).stream()
                .filter(row -> deviceId.equals(row.getDeviceId()))
                .findFirst()
                .ifPresent(row -> {
                    if (row.getSteps() != null) {
                        capabilities.markVerified(userId, deviceId, "STEPS", null);
                    }
                    if (row.getDistanceMeters() != null) {
                        capabilities.markVerified(userId, deviceId, "DISTANCE", null);
                    }
                    if (row.getCaloriesKcal() != null) {
                        capabilities.markVerified(userId, deviceId, "CALORIES", null);
                    }
                    if (row.getActiveMinutes() != null) {
                        capabilities.markVerified(userId, deviceId, "ACTIVE_MINUTES", null);
                    }
                });

        sleepSessions.findFirstByUserIdOrderByStartTimeDesc(userId)
                .filter(row -> deviceId.equals(row.getDeviceId()))
                .ifPresent(row -> {
                    capabilities.markVerified(userId, deviceId, "SLEEP", null);
                    if (row.getStageMinutes() != null && !row.getStageMinutes().isEmpty()) {
                        capabilities.markVerified(userId, deviceId, "SLEEP_STAGES", null);
                    }
                });
    }

    private void markReadingVerified(String userId, String deviceId,
                                     HealthMetricType type, String capability) {
        readings.findFirstByUserIdAndDeviceIdAndMetricTypeOrderByTimestampDesc(
                        userId, deviceId, type)
                .ifPresent(row -> capabilities.markVerified(userId, deviceId, capability, null));
    }

    private ZoneId zone() {
        return ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
    }

    private static int clampDays(Integer daysParam) {
        int days = daysParam == null ? DEFAULT_HISTORY_DAYS : daysParam;
        return Math.min(Math.max(days, 1), MAX_HISTORY_DAYS);
    }

    private static Double intOrNull(Integer value) {
        return value == null ? null : value.doubleValue();
    }
}
