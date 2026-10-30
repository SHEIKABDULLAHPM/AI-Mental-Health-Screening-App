package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Batch synchronization payload produced by the client Sync Manager after
 * BLE decode + validation. The server re-validates everything: client-side
 * validation is a convenience, never a security boundary.
 */
public record SyncRequest(
        @NotBlank @Size(max = 64) String clientSyncId,
        @NotBlank String deviceId,
        @Valid DeviceStatusInput deviceStatus,
        @Valid List<ReadingInput> readings,
        @Valid List<DailyActivityInput> dailyActivity,
        @Valid List<SleepInput> sleepSessions,
        @Valid List<ExerciseInput> exerciseSessions,
        @Size(max = 64) String clientError) {

    public record DeviceStatusInput(
            Integer batteryLevel,
            Boolean charging,
            String connectionStatus,
            @Size(max = 64) String firmwareVersion) {
    }

    public record ReadingInput(
            @NotBlank String metricType,
            @NotNull Double value,
            String unit,
            @NotNull Instant timestamp,
            Instant recordedAt,
            String measurementType) {
    }

    public record DailyActivityInput(
            @NotNull LocalDate date,
            Integer steps,
            Double distance,
            String distanceUnit,
            Double calories,
            Integer activeMinutes,
            /**
             * How to combine this row with an existing day. `INTERVAL_DELTA`
             * means the values are the sum of only the chunks fetched since the
             * last sync and must be added to the stored total. Anything else
             * (including null) keeps the legacy behaviour where the values are
             * authoritative cumulative totals that replace the stored row.
             */
            String aggregation) {
    }

    public record SleepInput(
            @NotNull Instant startTime,
            @NotNull Instant endTime,
            Long durationMillis,
            /**
             * Source-native stage durations in minutes. Keys are the labels the
             * device actually reported (canonical AWAKE/LIGHT/DEEP/REM when the
             * provider maps them, otherwise raw codes such as RAW_1).
             */
            java.util.Map<String, Integer> stageMinutes,
            @Size(max = 40) String stageSource,
            String measurementType) {
    }

    public record ExerciseInput(
            String type,
            @NotNull Instant startTime,
            @NotNull Instant endTime,
            Long durationMillis,
            Double distance,
            String distanceUnit,
            Double calories,
            Double averageHeartRate,
            Double maximumHeartRate) {
    }
}
