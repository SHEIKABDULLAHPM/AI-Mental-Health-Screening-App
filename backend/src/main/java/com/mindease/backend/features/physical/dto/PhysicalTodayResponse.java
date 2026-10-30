package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import com.mindease.backend.features.physical.domain.ConnectionStatus;
import com.mindease.backend.features.physical.domain.SyncStatus;
import com.mindease.backend.features.physical.domain.WearableProvider;

/**
 * The one payload the Physical Wellness dashboard renders for "today".
 *
 * <p>Every metric block distinguishes three states:</p>
 * <ul>
 *   <li>{@code supported=false} — the device does not expose this metric;</li>
 *   <li>{@code supported=true, value=null} — supported but no data received yet;</li>
 *   <li>{@code value=<number>} — real data (a genuine 0 is shown as 0).</li>
 * </ul>
 * Fake zeros are never produced.
 */
public record PhysicalTodayResponse(
        LocalDate date,
        DeviceBlock device,
        MetricBlock steps,
        MetricBlock distance,
        MetricBlock calories,
        HeartRateBlock heartRate,
        SleepBlock sleep,
        ExerciseBlock exercise,
        MetricBlock activeMinutes,
        MetricBlock spo2,
        MetricBlock hrv,
        SyncBlock sync) {

    public record DeviceBlock(
            String id,
            WearableProvider provider,
            String manufacturer,
            String model,
            String firmwareVersion,
            ConnectionStatus connectionStatus,
            Integer batteryLevel,
            Boolean charging,
            Instant lastSyncedAt) {
    }

    public record MetricBlock(boolean supported, Double value, String unit, Instant updatedAt) {
        public static MetricBlock unsupported(String unit) {
            return new MetricBlock(false, null, unit, null);
        }

        public static MetricBlock noData(String unit) {
            return new MetricBlock(true, null, unit, null);
        }
    }

    public record HeartRateBlock(
            boolean supported,
            Double latest,
            Double averageToday,
            Double resting,
            String unit,
            Instant updatedAt) {
    }

    public record SleepBlock(
            boolean supported,
            Long durationMillis,
            Instant bedtime,
            Instant wakeTime,
            LocalDate date,
            Instant updatedAt,
            /**
             * Source-native stage durations in minutes, keyed by the label the
             * device reported. {@code null} when the device reports no stages;
             * never inferred from total sleep.
             */
            java.util.Map<String, Integer> stageMinutes,
            String stageSource) {
    }

    public record ExerciseBlock(
            boolean supported, Long durationMillis, int sessionCount, Instant updatedAt) {
    }

    public record SyncBlock(
            Instant lastSyncedAt,
            Instant lastAttemptedAt,
            SyncStatus lastStatus,
            String lastError) {
    }
}
