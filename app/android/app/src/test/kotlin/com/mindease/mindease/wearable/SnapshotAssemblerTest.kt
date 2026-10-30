/*
 * JVM unit tests for the snapshot aggregation rules: sleep-chunk merging,
 * step-chunk rollups, day-totals fallback precedence, and heart-rate
 * filtering/timestamping. Pure JVM — no Android framework, no BLE.
 */
package com.mindease.mindease.wearable

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class SnapshotAssemblerTest {

    private val zone = ZoneId.of("UTC")
    private val day = LocalDate.of(2026, 10, 5)

    private fun sleepAt(date: LocalDate = day, minutesOfDay: Int, kind: Int = 1) =
        FitProProtocol.SleepChunk(date, minutesOfDay, kind)

    private fun step(
        steps: Int,
        caloriesKcal: Double = 10.0,
        distanceMeters: Int = 100,
        activeMinutes: Int = 5,
        minutesOfDay: Int = 0,
    ) = FitProProtocol.StepChunk(day, minutesOfDay, steps, caloriesKcal, distanceMeters, activeMinutes, 0)

    // ── Sleep merging ────────────────────────────────────────────────────

    @Test
    fun contiguousChunksMergeIntoOneSession() {
        val sessions = SnapshotAssembler.buildSleepSessions(
            listOf(sleepAt(minutesOfDay = 1320), sleepAt(minutesOfDay = 1335), sleepAt(minutesOfDay = 1350)),
            zone,
        )
        assertEquals(1, sessions.size)
        assertEquals("2026-10-05T22:00:00Z", sessions[0]["startTime"])
        assertEquals("2026-10-05T22:45:00Z", sessions[0]["endTime"])
        assertEquals(45 * 60_000L, sessions[0]["durationMillis"])
    }

    @Test
    fun gapSplitsSessionsInsteadOfFabricatingContinuity() {
        val sessions = SnapshotAssembler.buildSleepSessions(
            listOf(sleepAt(minutesOfDay = 1320), sleepAt(minutesOfDay = 1335), sleepAt(minutesOfDay = 1380)),
            zone,
        )
        assertEquals(2, sessions.size)
        assertEquals(30 * 60_000L, sessions[0]["durationMillis"])
        assertEquals("2026-10-05T23:00:00Z", sessions[1]["startTime"])
        assertEquals(15 * 60_000L, sessions[1]["durationMillis"])
    }

    @Test
    fun midnightCrossingStartsANewSession() {
        val sessions = SnapshotAssembler.buildSleepSessions(
            listOf(
                sleepAt(date = day, minutesOfDay = 1425),
                sleepAt(date = day.plusDays(1), minutesOfDay = 0),
                sleepAt(date = day.plusDays(1), minutesOfDay = 15),
            ),
            zone,
        )
        assertEquals(2, sessions.size)
        assertEquals("2026-10-05T23:45:00Z", sessions[0]["startTime"])
        assertEquals("2026-10-06T00:00:00Z", sessions[1]["startTime"])
        assertEquals("2026-10-06T00:30:00Z", sessions[1]["endTime"])
    }

    @Test
    fun unsortedChunksStillMerge() {
        val sessions = SnapshotAssembler.buildSleepSessions(
            listOf(sleepAt(minutesOfDay = 1335), sleepAt(minutesOfDay = 1320)),
            zone,
        )
        assertEquals(1, sessions.size)
        assertEquals(30 * 60_000L, sessions[0]["durationMillis"])
    }

    @Test
    fun noChunksMeansNoSessionsNeverPlaceholders() {
        assertTrue(SnapshotAssembler.buildSleepSessions(emptyList(), zone).isEmpty())
    }

    // ── Daily activity ───────────────────────────────────────────────────

    @Test
    fun stepChunksSumIntoAuthoritativeDailyTotals() {
        val daily = SnapshotAssembler.buildDailyActivity(
            listOf(step(100), step(200, caloriesKcal = 20.0, distanceMeters = 300, activeMinutes = 7)),
            zone,
        )!!
        assertEquals("2026-10-05", daily["date"])
        assertEquals(300, daily["steps"])
        assertEquals(400.0, daily["distance"])
        assertEquals("m", daily["distanceUnit"])
        assertEquals(30.0, daily["calories"])
        assertEquals(12, daily["activeMinutes"])
    }


    @Test
    fun multiDayHistoryProducesOneRowPerDate() {
        val rows = SnapshotAssembler.buildDailyActivities(
            listOf(
                FitProProtocol.StepChunk(day, 0, 100, 10.0, 100, 5, 0),
                FitProProtocol.StepChunk(day, 15, 250, 20.0, 200, 5, 0),
                FitProProtocol.StepChunk(day.minusDays(1), 0, 700, 40.0, 900, 10, 0),
            ),
            zone,
        )
        assertEquals(2, rows.size)
        assertEquals("2026-10-04", rows[0]["date"])
        assertEquals(700, rows[0]["steps"])
        assertEquals("2026-10-05", rows[1]["date"])
        assertEquals(350, rows[1]["steps"])
        assertEquals(10, rows[1]["activeMinutes"])
    }

    @Test
    fun noChunksAndNoTotalsMeansNull() {
        assertNull(SnapshotAssembler.buildDailyActivity(emptyList(), zone))
    }

    @Test
    fun chunksOutsideTheNinetyDayWindowAreDropped() {
        // The band replays factory chunks dated 2023; the backend rejects them
        // (MAX_AGE) and the whole sync turns PARTIAL for no user benefit.
        val rows = SnapshotAssembler.buildDailyActivities(
            listOf(
                FitProProtocol.StepChunk(LocalDate.of(2023, 1, 1), 0, 14, 0.2, 9, 0, 0),
                FitProProtocol.StepChunk(day, 0, 100, 0.1, 69, 5, 0),
            ),
            zone,
        )
        assertEquals(1, rows.size)
        assertEquals("2026-10-05", rows[0]["date"])
        assertEquals(100, rows[0]["steps"])
        assertEquals(0.1, rows[0]["calories"])
    }

    // ── Heart rate ───────────────────────────────────────────────────────

    @Test
    fun heartRateSamplesTimestampAndFilter() {
        val readings = SnapshotAssembler.buildHeartRateReadings(
            listOf(
                day to FitProProtocol.HeartRateSample(28_800, 72, 70, 110, 98),
                day to FitProProtocol.HeartRateSample(29_000, 0, 0, 0, 0),
            ),
            zone,
        )
        assertEquals(2, readings.size)
        assertEquals("HEART_RATE", readings[0]["metricType"])
        assertEquals(72.0, readings[0]["value"])
        assertEquals("2026-10-05T08:00:00Z", readings[0]["timestamp"])
        assertEquals("bpm", readings[0]["unit"])
        assertEquals("SPO2", readings[1]["metricType"])
    }

    @Test
    fun heartRateSamplesEmitDocumentedSpo2() {
        // Gadgetbridge reads the blood-oxygen byte from the same frame at
        // offset 13 and stores it via setSpo2Percent, so a sample in the
        // physiological range is a real measurement, not a guess.
        val readings = SnapshotAssembler.buildHeartRateReadings(
            listOf(day to FitProProtocol.HeartRateSample(28_800, 72, 70, 110, 98)),
            zone,
        )
        val spo2 = readings.single { it["metricType"] == "SPO2" }
        assertEquals(98.0, spo2["value"])
        assertEquals("%", spo2["unit"])
        assertEquals("2026-10-05T08:00:00Z", spo2["timestamp"])
    }

    @Test
    fun outOfRangeSpo2IsNotEmitted() {
        // 0 means "sensor not measuring"; 101+ cannot be a real saturation.
        val readings = SnapshotAssembler.buildHeartRateReadings(
            listOf(
                day to FitProProtocol.HeartRateSample(28_800, 72, 70, 110, 0),
                day to FitProProtocol.HeartRateSample(28_900, 73, 70, 110, 101),
            ),
            zone,
        )
        assertTrue(readings.none { it["metricType"] == "SPO2" })
    }

    // ── Sleep stages ─────────────────────────────────────────────────────

    @Test
    fun sleepSessionsCarrySourceNativeStageMinutes() {
        val sessions = SnapshotAssembler.buildSleepSessions(
            listOf(
                sleepAt(minutesOfDay = 1320, kind = 2),
                sleepAt(minutesOfDay = 1335, kind = 2),
                sleepAt(minutesOfDay = 1350, kind = 1),
            ),
            zone,
        )
        assertEquals(1, sessions.size)
        @Suppress("UNCHECKED_CAST")
        val stages = sessions[0]["stageMinutes"] as Map<String, Int>
        assertEquals(30, stages["RAW_2"])
        assertEquals(15, stages["RAW_1"])
        assertEquals("FITPRO_RAW", sessions[0]["stageSource"])
        // Stage minutes must add up to the session duration, never exceed it.
        assertEquals(45, stages.values.sum())
    }

    @Test
    fun stagesAreScopedPerSessionNotLeakedAcrossGaps() {
        val sessions = SnapshotAssembler.buildSleepSessions(
            listOf(
                sleepAt(minutesOfDay = 1320, kind = 1),
                sleepAt(minutesOfDay = 1380, kind = 3),
            ),
            zone,
        )
        @Suppress("UNCHECKED_CAST")
        val first = sessions[0]["stageMinutes"] as Map<String, Int>
        @Suppress("UNCHECKED_CAST")
        val second = sessions[1]["stageMinutes"] as Map<String, Int>
        assertEquals(mapOf("RAW_1" to 15), first)
        assertEquals(mapOf("RAW_3" to 15), second)
    }

    // ── Capability report ────────────────────────────────────────────────

    @Test
    fun capabilityReportOnlyIncludesObservedMetrics() {
        val report = SnapshotAssembler.buildCapabilityReport(
            hasBatteryLevel = true,
            hasFirmwareVersion = true,
            hasModelName = false,
            hasStepChunks = true,
            hasHeartRate = true,
            hasSleep = false,
        )
        val metrics = report.map { it["metric"] as String }
        assertTrue(metrics.containsAll(
            listOf("BATTERY_LEVEL", "FIRMWARE_INFO", "STEPS", "DISTANCE",
                "CALORIES", "ACTIVE_MINUTES", "HEART_RATE")))
        assertFalse(metrics.contains("DEVICE_MODEL"))
        assertFalse(metrics.contains("SLEEP"))
        assertFalse(metrics.contains("SLEEP_STAGES"))
        assertFalse(metrics.contains("GPS_ROUTE"))
    }

    @Test
    fun capabilityReportNeverClaimsVerification() {
        val report = SnapshotAssembler.buildCapabilityReport(
            hasBatteryLevel = true,
            hasFirmwareVersion = true,
            hasModelName = true,
            hasStepChunks = true,
            hasHeartRate = true,
            hasSleep = true,
        )
        assertTrue(report.isNotEmpty())
        assertTrue(report.all { it["supportStatus"] == "SUPPORTED_UNVERIFIED" })
        assertTrue(report.all { (it["limitations"] as String).isNotBlank() })
    }

    @Test
    fun spo2CapabilityOnlyWhenObserved() {
        val observed = SnapshotAssembler.buildCapabilityReport(
            hasBatteryLevel = false,
            hasFirmwareVersion = false,
            hasModelName = false,
            hasStepChunks = false,
            hasHeartRate = true,
            hasSleep = false,
            hasSpo2 = true,
        )
        assertTrue(observed.any { it["metric"] == "SPO2" })
        val notObserved = SnapshotAssembler.buildCapabilityReport(
            hasBatteryLevel = false,
            hasFirmwareVersion = false,
            hasModelName = false,
            hasStepChunks = false,
            hasHeartRate = true,
            hasSleep = false,
        )
        assertFalse(notObserved.any { it["metric"] == "SPO2" })
    }

    @Test
    fun emptySessionReportsNoCapabilities() {
        val report = SnapshotAssembler.buildCapabilityReport(
            hasBatteryLevel = false,
            hasFirmwareVersion = false,
            hasModelName = false,
            hasStepChunks = false,
            hasHeartRate = false,
            hasSleep = false,
        )
        assertTrue(report.isEmpty())
    }
}
