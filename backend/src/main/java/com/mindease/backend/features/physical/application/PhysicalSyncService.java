package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.ExerciseSession;
import com.mindease.backend.features.physical.domain.ExerciseSessionRepository;
import com.mindease.backend.features.physical.domain.HealthMetricType;
import com.mindease.backend.features.physical.domain.HealthReading;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.MeasurementType;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.domain.SyncSession;
import com.mindease.backend.features.physical.domain.SyncSessionRepository;
import com.mindease.backend.features.physical.domain.SyncStatus;
import com.mindease.backend.features.physical.domain.WearableDevice;
import com.mindease.backend.features.physical.domain.WearableDeviceRepository;
import com.mindease.backend.features.physical.dto.SyncRequest;
import com.mindease.backend.features.physical.dto.SyncResponse;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Reliable synchronization ingest: decode output → validate → deduplicate →
 * persist → record sync outcome.
 *
 * <p>Every record is re-validated server-side. Duplicates (replayed batches,
 * reconnect resends) are detected through the unique indexes and counted, not
 * rejected as errors. Validation failures are rejected with a category, index
 * and user-safe reason — they are never stored.</p>
 */
@Service
public class PhysicalSyncService {

    private static final Logger log = LoggerFactory.getLogger(PhysicalSyncService.class);

    private static final int MAX_BATCH_RECORDS = 5_000;
    private static final int MAX_ERROR_LENGTH = 500;

    private final WearableDeviceRepository devices;
    private final WearableDeviceService deviceService;
    private final HealthReadingRepository readings;
    private final DailyActivityRepository dailyActivity;
    private final SleepSessionRepository sleepSessions;
    private final ExerciseSessionRepository exerciseSessions;
    private final SyncSessionRepository syncSessions;
    private final HealthDataValidator validator;

    public PhysicalSyncService(WearableDeviceRepository devices,
                               WearableDeviceService deviceService,
                               HealthReadingRepository readings,
                               DailyActivityRepository dailyActivity,
                               SleepSessionRepository sleepSessions,
                               ExerciseSessionRepository exerciseSessions,
                               SyncSessionRepository syncSessions,
                               HealthDataValidator validator) {
        this.devices = devices;
        this.deviceService = deviceService;
        this.readings = readings;
        this.dailyActivity = dailyActivity;
        this.sleepSessions = sleepSessions;
        this.exerciseSessions = exerciseSessions;
        this.syncSessions = syncSessions;
        this.validator = validator;
    }

    public SyncResponse sync(String userId, SyncRequest request) {
        WearableDevice device = deviceService.requireOwned(userId, request.deviceId());
        Instant now = Instant.now();
        ZoneId zone = ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());

        int received = size(request.readings()) + size(request.dailyActivity())
                + size(request.sleepSessions()) + size(request.exerciseSessions());
        if (received > MAX_BATCH_RECORDS) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Sync batch exceeds the maximum of " + MAX_BATCH_RECORDS + " records");
        }

        // Batch idempotency: a client that never received the first response
        // (dropped connection right after upload) replays the whole batch. The
        // records were already stored, so the replay must not re-stamp the
        // device, grow the audit log, or manufacture a fresh session — the
        // original outcome is echoed back with every record counted as a
        // duplicate re-send.
        SyncSession replayed = syncSessions
                .findFirstByUserIdAndClientSyncId(userId, request.clientSyncId())
                .orElse(null);
        if (replayed != null
                && (replayed.getStatus() == SyncStatus.SUCCESS
                        || replayed.getStatus() == SyncStatus.PARTIAL)) {
            log.info("Sync replay {} for device {}: echoing stored result {}",
                    request.clientSyncId(), device.getId(), replayed.getStatus());
            return new SyncResponse(replayed.getId(), replayed.getStatus(), received,
                    0, received, 0, List.of(), replayed.getCompletedAt());
        }

        List<SyncResponse.Rejection> rejections = new ArrayList<>();
        int[] counters = new int[] {0, 0, 0}; // accepted, duplicates, rejected

        // Sum of newly accepted interval readings per local day (used when the
        // device does not send authoritative cumulative daily totals).
        Map<LocalDate, double[]> intervalSums = new HashMap<>();

        persistReadings(userId, device, request.readings(), zone, now, rejections, counters,
                intervalSums);
        Set<LocalDate> coveredDates = persistDailyActivity(userId, device, request.dailyActivity(),
                zone, rejections, counters, intervalSums);
        applyIntervalSums(userId, device, intervalSums, coveredDates);
        persistSleep(userId, device, request.sleepSessions(), zone, rejections, counters);
        persistExercise(userId, device, request.exerciseSessions(), zone, rejections, counters);
        applyDeviceStatus(device, request.deviceStatus(), now);

        int accepted = counters[0];
        int duplicates = counters[1];
        int rejected = counters[2];
        SyncStatus status = rejected == 0
                ? SyncStatus.SUCCESS
                : (accepted > 0 ? SyncStatus.PARTIAL : SyncStatus.FAILED);

        SyncSession session = new SyncSession();
        session.setUserId(userId);
        session.setDeviceId(device.getId());
        session.setProvider(device.getProvider());
        session.setClientSyncId(request.clientSyncId());
        session.setStatus(status);
        session.setStartedAt(now);
        session.setCompletedAt(Instant.now());
        session.setRecordsReceived(received);
        session.setRecordsAccepted(accepted);
        session.setRecordsRejected(rejected);
        session.setRetryCount(0);
        if (request.clientError() != null && !request.clientError().isBlank()) {
            session.setError(truncate(request.clientError()));
        } else if (status == SyncStatus.FAILED && rejected > 0 && !rejections.isEmpty()) {
            session.setError(truncate(rejections.get(0).reason()));
        }
        syncSessions.save(session);

        device.setLastSyncedAt(session.getCompletedAt());
        device.setUpdatedAt(session.getCompletedAt());
        applyDeviceStatusSave(device);
        log.info("Sync {} for device {}: received={} accepted={} duplicates={} rejected={}",
                status, device.getId(), received, accepted, duplicates, rejected);

        return new SyncResponse(session.getId(), status, received, accepted, duplicates,
                rejected, rejections, session.getCompletedAt());
    }

    private void persistReadings(String userId, WearableDevice device,
                                 List<SyncRequest.ReadingInput> inputs, ZoneId zone, Instant now,
                                 List<SyncResponse.Rejection> rejections, int[] counters,
                                 Map<LocalDate, double[]> intervalSums) {
        if (inputs == null) {
            return;
        }
        for (int i = 0; i < inputs.size(); i++) {
            SyncRequest.ReadingInput input = inputs.get(i);
            HealthMetricType metricType = HealthMetricType.fromApiName(input.metricType());
            HealthDataValidator.Outcome outcome =
                    validator.validateReading(metricType, input.value(), input.unit(),
                            input.timestamp(), now);
            if (!outcome.valid()) {
                reject(rejections, counters, "reading", i, outcome.error());
                continue;
            }
            HealthReading reading = new HealthReading();
            reading.setUserId(userId);
            reading.setDeviceId(device.getId());
            reading.setSource(device.getProvider());
            reading.setMetricType(metricType);
            reading.setValue(outcome.value());
            reading.setUnit(outcome.unit());
            reading.setTimestamp(input.timestamp());
            reading.setDate(input.timestamp().atZone(zone).toLocalDate());
            reading.setRecordedAt(input.recordedAt() != null ? input.recordedAt() : now);
            reading.setMeasurementType(measurementType(input.measurementType(),
                    MeasurementType.DEVICE_MEASURED));
            try {
                readings.save(reading);
                counters[0]++;
                accumulate(intervalSums, reading.getDate(), metricType, outcome.value());
            } catch (DuplicateKeyException e) {
                counters[1]++;
            }
        }
    }

    private Set<LocalDate> persistDailyActivity(String userId, WearableDevice device,
                                      List<SyncRequest.DailyActivityInput> inputs, ZoneId zone,
                                      List<SyncResponse.Rejection> rejections, int[] counters,
                                      Map<LocalDate, double[]> intervalSums) {
        Set<LocalDate> coveredDates = new HashSet<>();
        if (inputs == null) {
            return coveredDates;
        }
        for (int i = 0; i < inputs.size(); i++) {
            SyncRequest.DailyActivityInput input = inputs.get(i);
            if (input.date() == null) {
                reject(rejections, counters, "dailyActivity", i, "Date is required");
                continue;
            }
            if (input.date().isAfter(LocalDate.now(zone)) || input.date().isBefore(LocalDate.now(zone).minusDays(95))) {
                reject(rejections, counters, "dailyActivity", i, "Date is outside the supported window");
                continue;
            }
            Integer steps = input.steps();
            if (steps != null && (steps < 0 || steps > HealthDataValidator.MAX_STEPS_PER_DAY)) {
                reject(rejections, counters, "dailyActivity", i, "Steps are outside the plausible range");
                continue;
            }
            Double distanceMeters = null;
            if (input.distance() != null) {
                HealthDataValidator.Outcome outcome = validator.normalizeAndRange(
                        HealthMetricType.DISTANCE, input.distance(), input.distanceUnit());
                if (!outcome.valid()) {
                    reject(rejections, counters, "dailyActivity", i, outcome.error());
                    continue;
                }
                distanceMeters = outcome.value();
            }
            Double calories = null;
            if (input.calories() != null) {
                HealthDataValidator.Outcome outcome = validator.normalizeAndRange(
                        HealthMetricType.CALORIES, input.calories(), "kcal");
                if (!outcome.valid()) {
                    reject(rejections, counters, "dailyActivity", i, outcome.error());
                    continue;
                }
                calories = outcome.value();
            }
            if (input.activeMinutes() != null
                    && (input.activeMinutes() < 0 || input.activeMinutes() > 1440)) {
                reject(rejections, counters, "dailyActivity", i, "Active minutes are outside the plausible range");
                continue;
            }

            DailyActivity existing = dailyActivity.findByUserIdAndDate(userId, input.date())
                    .orElseGet(DailyActivity::new);
            double[] sums = intervalSums.get(input.date());
            // Cumulative device totals are authoritative (they replace); interval
            // readings are added on top of whatever is already stored, and a day
            // with no data at all stays null instead of becoming a fake zero.
            applyDailyActivityRow(existing, device, userId, input.date(), input,
                    distanceMeters, calories, sums);
            Instant stamp = Instant.now();
            if (existing.getId() == null) {
                existing.setCreatedAt(stamp);
            }
            existing.setUpdatedAt(stamp);
            // The unique index `uq_user_day` is the dedupe authority; a
            // concurrent or replayed batch can win the insert between the
            // find and the save. Re-merging over the stored row keeps the
            // batch a success (counted, not an HTTP 500), like the readings
            // and sleep paths.
            DailyActivity stored = saveDailyActivityMerge(userId, input.date(), existing);
            if (stored != null) {
                coveredDates.add(input.date());
                counters[0]++;
            }
        }
        return coveredDates;
    }

    /**
     * Applies one batch row's authoritative totals (device-supplied daily
     * values replace) plus any interval sums accumulated for that date onto
     * `target`. Verified callers always pass validated, non-null values.
     */
    private void applyDailyActivityRow(DailyActivity target, WearableDevice device,
                                       String userId, LocalDate date,
                                       SyncRequest.DailyActivityInput input,
                                       Double distanceMeters, Double calories, double[] sums) {
        target.setUserId(userId);
        target.setDeviceId(device.getId());
        target.setSource(device.getProvider());
        target.setDate(date);
        // Cumulative device totals are authoritative (they replace); interval
        // readings are added on top of whatever is already stored, and a day
        // with no data at all stays null instead of becoming a fake zero.
        //
        // FitPro deletes history from the band after sending it once, so each
        // fetch contains only the *new* chunks since the previous sync. Such a
        // row is marked INTERVAL_DELTA and must be added: replacing the stored
        // day with only the new chunks silently dropped the earlier total
        // (423 steps stored at 19:34, next fetch's 701-step delta replaced it).
        boolean intervalDelta = "INTERVAL_DELTA".equalsIgnoreCase(input.aggregation());
        double extraSteps = input.steps() != null ? input.steps() : 0;
        double extraDistance = distanceMeters != null ? distanceMeters : 0;
        double extraCalories = calories != null ? calories : 0;
        if (intervalDelta) {
            target.setSteps(mergeSteps(target.getSteps(),
                    extraSteps + (sums == null ? 0 : sums[0])));
            target.setDistanceMeters(mergeDouble(target.getDistanceMeters(),
                    extraDistance + (sums == null ? 0 : sums[1])));
            target.setCaloriesKcal(mergeDouble(target.getCaloriesKcal(),
                    extraCalories + (sums == null ? 0 : sums[2])));
        } else {
            target.setSteps(input.steps() != null ? input.steps()
                    : mergeSteps(target.getSteps(), sums == null ? 0 : sums[0]));
            target.setDistanceMeters(distanceMeters != null ? distanceMeters
                    : mergeDouble(target.getDistanceMeters(), sums == null ? 0 : sums[1]));
            target.setCaloriesKcal(calories != null ? calories
                    : mergeDouble(target.getCaloriesKcal(), sums == null ? 0 : sums[2]));
        }
        if (input.activeMinutes() != null) {
            target.setActiveMinutes(intervalDelta
                    ? mergeSteps(target.getActiveMinutes(), input.activeMinutes())
                    : input.activeMinutes());
        }
    }

    /**
     * Saves a daily row, and when the insert loses the `uq_user_day`
     * unique-index race re-reads the stored winner and re-setValue merges the
     * batch values over it. Returns the stored row, or null when even the
     * merge could not be written (logged: the day is stored by the winner
     * already, and bookkeeping must never turn a legal replay into an
     * HTTP 500).
     */
    private DailyActivity saveDailyActivityMerge(String userId, LocalDate date,
                                                 DailyActivity row) {
        Instant stamp = row.getUpdatedAt();
        try {
            return dailyActivity.save(row);
        } catch (DuplicateKeyException e) {
            DailyActivity winner = dailyActivity.findByUserIdAndDate(userId, date)
                    .orElse(null);
            if (winner == null) {
                log.warn("Daily activity upsert lost the unique-index race for {} on {} "
                        + "and the row is no longer readable; createdAt preserved.",
                        userId, date);
                return null;
            }
            // Re-apply the batch values (authoreplace semantics + merged sums)
            // over whatever the other writer stored, then retry once.
            remergeLoserOntoWinner(row, winner);
            winner.setUpdatedAt(stamp);
            try {
                return dailyActivity.save(winner);
            } catch (DuplicateKeyException retryFailure) {
                log.warn("Daily activity merge lost the unique-index race twice for {} on {}: {}",
                        userId, date, retryFailure.getMessage());
                return null;
            }
        }
    }

    /**
     * Copies a conflict-loser's computed values onto the stored winner row.
     * Null fields mean "no value claimed by this batch", so the winner's own
     * values are kept — a replay that shares the batch values is idempotent,
     * and a genuinely new batch always carries non-null authoritative values.
     */
    private static void remergeLoserOntoWinner(DailyActivity loser, DailyActivity winner) {
        if (loser.getSteps() != null) {
            winner.setSteps(loser.getSteps());
        }
        if (loser.getDistanceMeters() != null) {
            winner.setDistanceMeters(loser.getDistanceMeters());
        }
        if (loser.getCaloriesKcal() != null) {
            winner.setCaloriesKcal(loser.getCaloriesKcal());
        }
        if (loser.getActiveMinutes() != null) {
            winner.setActiveMinutes(loser.getActiveMinutes());
        }
        if (winner.getCreatedAt() == null) {
            winner.setCreatedAt(loser.getCreatedAt());
        }
    }

    /**
     * Upserts daily rows for days that only received interval readings (the
     * batch contained no authoritative daily total for them). Rows created
     * here derive from readings already counted, so counters are untouched.
     */
    private void applyIntervalSums(String userId, WearableDevice device,
                                   Map<LocalDate, double[]> intervalSums,
                                   Set<LocalDate> coveredDates) {
        for (Map.Entry<LocalDate, double[]> entry : intervalSums.entrySet()) {
            LocalDate date = entry.getKey();
            if (coveredDates.contains(date)) {
                continue;
            }
            double[] sums = entry.getValue();
            if (sums[0] == 0 && sums[1] == 0 && sums[2] == 0) {
                continue;
            }
            DailyActivity existing = dailyActivity.findByUserIdAndDate(userId, date)
                    .orElseGet(DailyActivity::new);
            existing.setUserId(userId);
            existing.setDeviceId(device.getId());
            existing.setSource(device.getProvider());
            existing.setDate(date);
            existing.setSteps(mergeSteps(existing.getSteps(), sums[0]));
            existing.setDistanceMeters(mergeDouble(existing.getDistanceMeters(), sums[1]));
            existing.setCaloriesKcal(mergeDouble(existing.getCaloriesKcal(), sums[2]));
            Instant stamp = Instant.now();
            if (existing.getId() == null) {
                existing.setCreatedAt(stamp);
            }
            existing.setUpdatedAt(stamp);
            saveDailyActivityMerge(userId, date, existing);
        }
    }

    private void persistSleep(String userId, WearableDevice device,
                              List<SyncRequest.SleepInput> inputs, ZoneId zone,
                              List<SyncResponse.Rejection> rejections, int[] counters) {
        if (inputs == null) {
            return;
        }
        for (int i = 0; i < inputs.size(); i++) {
            SyncRequest.SleepInput input = inputs.get(i);
            HealthDataValidator.Outcome outcome = validator.validateSleep(
                    input.startTime(), input.endTime(), input.durationMillis(), now());
            if (!outcome.valid()) {
                reject(rejections, counters, "sleep", i, outcome.error());
                continue;
            }
            if (sleepSessions.findByUserIdAndDeviceIdAndStartTime(
                    userId, device.getId(), input.startTime()).isPresent()) {
                counters[1]++;
                continue;
            }
            SleepSession session = new SleepSession();
            session.setUserId(userId);
            session.setDeviceId(device.getId());
            session.setSource(device.getProvider());
            session.setStartTime(input.startTime());
            session.setEndTime(input.endTime());
            session.setDurationMillis((long) outcome.value());
            session.setDate(input.endTime().atZone(zone).toLocalDate());
            session.setRecordedAt(Instant.now());
            SensedStages stages = sanitizeStages(input, outcome.value());
            if (!stages.valid()) {
                reject(rejections, counters, "sleep", i, stages.error());
                continue;
            }
            session.setStageMinutes(stages.minutes());
            session.setStageSource(stages.source());
            try {
                sleepSessions.save(session);
                counters[0]++;
            } catch (DuplicateKeyException e) {
                counters[1]++;
            }
        }
    }

    /**
     * Validated stage breakdown. Stage minutes come straight from the device;
     * they are never derived from total sleep, and they may not exceed the
     * session duration (a mismatch means the decode or the provider is wrong,
     * so the session is rejected instead of storing contradictory data).
     */
    private record SensedStages(java.util.Map<String, Integer> minutes, String source,
                                boolean valid, String error) {
    }

    private static SensedStages sanitizeStages(SyncRequest.SleepInput input, double durationMillis) {
        java.util.Map<String, Integer> raw = input.stageMinutes();
        if (raw == null || raw.isEmpty()) {
            return new SensedStages(null, null, true, null);
        }
        if (raw.size() > 16) {
            return new SensedStages(null, null, false,
                    "At most 16 sleep stage entries are supported");
        }
        long total = 0;
        java.util.Map<String, Integer> clean = new java.util.LinkedHashMap<>();
        for (java.util.Map.Entry<String, Integer> entry : raw.entrySet()) {
            String label = entry.getKey() == null ? "" : entry.getKey().trim();
            Integer value = entry.getValue();
            if (label.isEmpty() || label.length() > 32
                    || !label.matches("[A-Za-z0-9_]+")) {
                return new SensedStages(null, null, false,
                        "Sleep stage labels must be 1-32 characters of A-Z, 0-9 or _");
            }
            if (value == null || value < 0 || value > 1440) {
                return new SensedStages(null, null, false,
                        "Sleep stage minutes must be between 0 and 1440");
            }
            total += value;
            clean.put(label.toUpperCase(java.util.Locale.ROOT), value);
        }
        long durationMinutes = Math.round(durationMillis / 60_000d);
        if (total > durationMinutes + 1) {
            return new SensedStages(null, null, false,
                    "Sleep stage minutes exceed the session duration");
        }
        String source = input.stageSource() == null || input.stageSource().isBlank()
                ? "UNSPECIFIED" : input.stageSource().trim().toUpperCase(java.util.Locale.ROOT);
        return new SensedStages(clean, source, true, null);
    }

    private void persistExercise(String userId, WearableDevice device,
                                 List<SyncRequest.ExerciseInput> inputs, ZoneId zone,
                                 List<SyncResponse.Rejection> rejections, int[] counters) {
        if (inputs == null) {
            return;
        }
        for (int i = 0; i < inputs.size(); i++) {
            SyncRequest.ExerciseInput input = inputs.get(i);
            HealthDataValidator.Outcome outcome = validator.validateExercise(
                    input.startTime(), input.endTime(), input.durationMillis(), now());
            if (!outcome.valid()) {
                reject(rejections, counters, "exercise", i, outcome.error());
                continue;
            }
            String hrError = firstNonNull(
                    validator.validateHeartRateOrNull(input.averageHeartRate()),
                    validator.validateHeartRateOrNull(input.maximumHeartRate()));
            if (hrError != null) {
                reject(rejections, counters, "exercise", i, hrError);
                continue;
            }
            if (exerciseSessions.findByUserIdAndDeviceIdAndStartTime(
                    userId, device.getId(), input.startTime()).isPresent()) {
                counters[1]++;
                continue;
            }
            Double distanceMeters = null;
            if (input.distance() != null) {
                HealthDataValidator.Outcome distance = validator.normalizeAndRange(
                        HealthMetricType.DISTANCE, input.distance(), input.distanceUnit());
                if (!distance.valid()) {
                    reject(rejections, counters, "exercise", i, distance.error());
                    continue;
                }
                distanceMeters = distance.value();
            }
            Double calories = null;
            if (input.calories() != null) {
                if (input.calories() < 0 || input.calories() > HealthDataValidator.MAX_CALORIES_PER_DAY) {
                    reject(rejections, counters, "exercise", i, "Calories are outside the plausible range");
                    continue;
                }
                calories = input.calories();
            }

            ExerciseSession session = new ExerciseSession();
            session.setUserId(userId);
            session.setDeviceId(device.getId());
            session.setSource(device.getProvider());
            session.setType(normalizeExerciseType(input.type()));
            session.setStartTime(input.startTime());
            session.setEndTime(input.endTime());
            session.setDurationMillis((long) outcome.value());
            session.setDate(input.startTime().atZone(zone).toLocalDate());
            session.setDistanceMeters(distanceMeters);
            session.setCaloriesKcal(calories);
            session.setAverageHeartRate(input.averageHeartRate());
            session.setMaximumHeartRate(input.maximumHeartRate());
            session.setRecordedAt(Instant.now());
            try {
                exerciseSessions.save(session);
                counters[0]++;
            } catch (DuplicateKeyException e) {
                counters[1]++;
            }
        }
    }

    private void applyDeviceStatus(WearableDevice device, SyncRequest.DeviceStatusInput status,
                                   Instant now) {
        if (status == null) {
            return;
        }
        String batteryError = validator.validateBattery(status.batteryLevel());
        if (batteryError == null && status.batteryLevel() != null) {
            device.setBatteryLevel(status.batteryLevel());
        }
        if (status.charging() != null) {
            device.setCharging(status.charging());
        }
        if (status.connectionStatus() != null) {
            ConnectionStatus connection = parseConnection(status.connectionStatus());
            if (connection != null) {
                device.setConnectionStatus(connection);
                if (connection == ConnectionStatus.CONNECTED) {
                    device.setLastConnectedAt(now);
                }
            }
        }
        if (status.firmwareVersion() != null && !status.firmwareVersion().isBlank()) {
            device.setFirmwareVersion(status.firmwareVersion().trim());
        }
        device.setLastSeenAt(now);
    }

    /**
     * The gateway device row is version-optimistically locked; two retries
     * arriving together can race on the same version. A save that lost the
     * race must not turn an otherwise-successful sync into an HTTP 500 — the
     * winner already wrote a superset of the status fields, so the loser only
     * logs and continues.
     */
    private void applyDeviceStatusSave(WearableDevice device) {
        try {
            devices.save(device);
        } catch (OptimisticLockingFailureException e) {
            log.warn("Sync status save lost the optimistic-lock race for device {}: {}",
                    device.getId(), e.getMessage());
        }
    }

    private void accumulate(Map<LocalDate, double[]> sums, LocalDate date,
                            HealthMetricType metricType, double value) {
        double[] entry = sums.computeIfAbsent(date, d -> new double[3]);
        switch (metricType) {
            case STEPS -> entry[0] += value;
            case DISTANCE -> entry[1] += value;
            case CALORIES -> entry[2] += value;
            default -> {
                // Heart rate, SpO2, HRV and other point metrics do not feed
                // daily activity totals.
            }
        }
    }

    /** Merges an existing daily total with newly accepted interval sums. */
    private static Integer mergeSteps(Integer existing, double intervalSum) {
        if (existing == null) {
            return intervalSum > 0 ? (int) intervalSum : null;
        }
        return existing + (int) intervalSum;
    }

    private static Double mergeDouble(Double existing, double intervalSum) {
        if (existing == null) {
            return intervalSum > 0 ? intervalSum : null;
        }
        return existing + intervalSum;
    }

    private void reject(List<SyncResponse.Rejection> rejections, int[] counters,
                        String category, int index, String reason) {
        rejections.add(new SyncResponse.Rejection(category, index,
                reason == null ? "Invalid record" : reason));
        counters[2]++;
    }

    private static MeasurementType measurementType(String raw, MeasurementType fallback) {
        if (raw == null || raw.isBlank()) {
            return fallback;
        }
        try {
            return MeasurementType.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            return fallback;
        }
    }

    private static ConnectionStatus parseConnection(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            return ConnectionStatus.valueOf(raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /** Only exercise types the device reliably identifies are preserved. */
    private static String normalizeExerciseType(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        String normalized = raw.trim().toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9_]", "_");
        return normalized.length() <= 32 ? normalized : null;
    }

    private static String firstNonNull(String first, String second) {
        return first != null ? first : second;
    }

    private static int size(List<?> list) {
        return list == null ? 0 : list.size();
    }

    private static Instant now() {
        return Instant.now();
    }

    private static String truncate(String value) {
        return value.length() <= MAX_ERROR_LENGTH ? value : value.substring(0, MAX_ERROR_LENGTH);
    }
}
