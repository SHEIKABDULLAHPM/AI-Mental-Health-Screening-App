/*
 * Pure-JVM assembly of a `readSnapshot()` payload from decoded FitPro frames.
 *
 * Extracted from `WearableChannel` so the aggregation rules — sleep-chunk
 * merging, step-chunk summation, day-totals fallback, heart-rate filtering —
 * are covered by plain JVM unit tests (`SnapshotAssemblerTest`) without
 * Android-framework fakes. The channel owns BLE/threading; this object owns
 * arithmetic. Behavior must stay byte-identical to what the channel produced
 * before the extraction.
 */
package com.mindease.mindease.wearable

import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

object SnapshotAssembler {

    /**
     * Merges 15-minute sleep chunks into sessions. Contiguous chunks on the
     * same band-local date join one session; any gap (or date change, which
     * also covers midnight crossings) starts a new session rather than
     * fabricating continuity.
     */
    fun buildSleepSessions(
        chunks: List<FitProProtocol.SleepChunk>,
        zone: ZoneId,
        isoInstant: DateTimeFormatter = DateTimeFormatter.ISO_INSTANT,
    ): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        var start: ZonedDateTime? = null
        var minutes = 0
        var lastDate: LocalDate? = null
        var lastMinutesOfDay = -1
        // Source-native stage minutes, keyed by the raw label the band emitted.
        // The FitPro protocol has no verified mapping from these codes to
        // awake/light/deep/REM, so they are preserved verbatim as RAW_<n>.
        var stageMinutes = LinkedHashMap<String, Int>()
        val sorted = chunks.sortedWith(compareBy({ it.date }, { it.minutesOfDay }))
        for (chunk in sorted) {
            val contiguous = lastDate == chunk.date && chunk.minutesOfDay == lastMinutesOfDay + 15
            if (contiguous) {
                minutes += 15
            } else {
                start?.let { out.add(session(it, minutes, stageMinutes, isoInstant)) }
                start = chunk.date.atTime(0, 0).atZone(zone).plusMinutes(chunk.minutesOfDay.toLong())
                minutes = 15
                stageMinutes = LinkedHashMap()
            }
            val label = "RAW_${chunk.kind}"
            stageMinutes[label] = (stageMinutes[label] ?: 0) + 15
            lastDate = chunk.date
            lastMinutesOfDay = chunk.minutesOfDay
        }
        start?.let { out.add(session(it, minutes, stageMinutes, isoInstant)) }
        return out
    }

    /**
     * Day-level activity rollup, or null when the band reported nothing.
     * Interval chunks win when present; otherwise the band's own day-totals
     * frame backfills steps/distance/calories. `activeMinutes` is omitted in
     * the fallback because the totals frame carries no such field — a zero
     * would read as "measured zero" instead of "unknown".
     *
     * Single-day convenience wrapper; the channel uses
     * [buildDailyActivities] so multi-day history is not collapsed into one
     * row.
     */
    fun buildDailyActivity(
        stepChunks: List<FitProProtocol.StepChunk>,
        zone: ZoneId,
        isoDate: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE,
    ): Map<String, Any?>? = buildDailyActivities(stepChunks, zone, isoDate)
        .firstOrNull()

    /**
     * One rollup row per band-local date. The band streams chunks for several
     * days in one fetch; summing them into a single row would misattribute
     * history and destroy the weekly trend. The band's 0x0c day-summary frame
     * is deliberately not used: its layout is unverified on V15183 and changed
     * between captured connections.
     *
     * Chunks dated in the future or older than 90 days (the backend's
     * `MAX_AGE`) are dropped: the band replays a few factory/test chunks dated
     * 2023 that the server would only reject, turning a good sync into a
     * needless PARTIAL.
     */
    fun buildDailyActivities(
        stepChunks: List<FitProProtocol.StepChunk>,
        zone: ZoneId,
        isoDate: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE,
    ): List<Map<String, Any?>> {
        val today = LocalDate.now(zone)
        val oldest = today.minusDays(90)
        val usableChunks = stepChunks.filter {
            !it.date.isBefore(oldest) && !it.date.isAfter(today)
        }
        if (usableChunks.isEmpty()) return emptyList()
        val byDate = usableChunks.groupBy { it.date }
        val out = ArrayList<Map<String, Any?>>()
        for ((date, chunks) in byDate.toSortedMap()) {
            out.add(
                mapOf(
                    "date" to isoDate.format(date),
                    "steps" to chunks.sumOf { it.steps },
                    "distance" to chunks.sumOf { it.distanceMeters }.toDouble(),
                    "distanceUnit" to "m",
                    "calories" to chunks.sumOf { it.caloriesKcal },
                    "activeMinutes" to chunks.sumOf { it.activeMinutes },
                ),
            )
        }
        return out
    }

    /**
     * Heart-rate and SpO2 readings. Non-positive HR values (band "no
     * measurement" sentinel) are dropped; each sample lands at band-local
     * midnight plus its seconds-of-day offset. The SpO2 byte at payload[5]
     * (full-frame offset 13 in Gadgetbridge, stored via `setSpo2Percent`) is
     * emitted only inside the plausible 50–100 % range — outside it the band
     * is reporting "not measuring", not a reading.
     */
    fun buildHeartRateReadings(
        samples: List<Pair<LocalDate, FitProProtocol.HeartRateSample>>,
        zone: ZoneId,
        isoInstant: DateTimeFormatter = DateTimeFormatter.ISO_INSTANT,
    ): List<Map<String, Any?>> {
        val readings = ArrayList<Map<String, Any?>>()
        for ((date, hr) in samples) {
            if (hr.heartRate <= 0) continue
            val ts = date.atTime(0, 0).atZone(zone)
                .plusSeconds(hr.timeOfDaySeconds.toLong())
                .toInstant()
            readings.add(
                mapOf(
                    "metricType" to "HEART_RATE",
                    "value" to hr.heartRate.toDouble(),
                    "timestamp" to isoInstant.format(ts),
                    "unit" to "bpm",
                    "measurementType" to "DEVICE_MEASURED",
                ),
            )
            if (hr.spo2 in 50..100) {
                readings.add(
                    mapOf(
                        "metricType" to "SPO2",
                        "value" to hr.spo2.toDouble(),
                        "timestamp" to isoInstant.format(ts),
                        "unit" to "%",
                        "measurementType" to "DEVICE_MEASURED",
                    ),
                )
            }
        }
        return readings
    }

    /**
     * Capability report for the server-side registry.
     *
     * Only what this session actually observed is reported, and nothing is
     * marked verified: the server downgrades any client claim of verification
     * anyway, and hardware support can only be confirmed by a documented
     * on-device validation run. Metrics the device does not expose are simply
     * absent here; the server seeds them as unsupported/unknown with notes.
     */
    fun buildCapabilityReport(
        hasBatteryLevel: Boolean,
        hasFirmwareVersion: Boolean,
        hasModelName: Boolean,
        hasStepChunks: Boolean,
        hasHeartRate: Boolean,
        hasSleep: Boolean,
        hasSpo2: Boolean = false,
    ): List<Map<String, Any?>> {
        val report = ArrayList<Map<String, Any?>>()
        fun add(metric: String, method: String, limitations: String) {
            report += mapOf(
                "metric" to metric,
                "supportStatus" to "SUPPORTED_UNVERIFIED",
                "retrievalMethod" to method,
                "limitations" to limitations,
            )
        }
        if (hasBatteryLevel) {
            add("BATTERY_LEVEL", "GATT_STANDARD",
                "Read from the standard battery service; level is only as fresh as the last read.")
        }
        if (hasFirmwareVersion) {
            add("FIRMWARE_INFO", "GATT_STANDARD",
                "Reported by the device-information service.")
        }
        if (hasModelName) {
            add("DEVICE_MODEL", "GATT_STANDARD",
                "Reported by the device-information service.")
        }
        if (hasStepChunks) {
            add("STEPS", "VENDOR_PROTOCOL",
                "Decoded from FitPro step frames; not yet confirmed against the vendor app on V15183.")
            add("DISTANCE", "VENDOR_PROTOCOL",
                "Derived from the band's own distance field; not GPS.")
            add("CALORIES", "VENDOR_PROTOCOL",
                "The band's own calorie estimate, not a clinical measurement.")
        }
        if (hasStepChunks) {
            add("ACTIVE_MINUTES", "VENDOR_PROTOCOL",
                "Derived from the band's per-chunk active-minute field.")
        }
        if (hasHeartRate) {
            add("HEART_RATE", "VENDOR_PROTOCOL",
                "Spot samples decoded from heart-rate frames; not continuous monitoring.")
        }
        if (hasSpo2) {
            add("SPO2", "VENDOR_PROTOCOL",
                "Blood-oxygen byte from the same heart-rate frames (Gadgetbridge reads it at frame offset 13); measured whenever the optical sensor takes a reading, not continuously.")
        }
        if (hasSleep) {
            add("SLEEP", "VENDOR_PROTOCOL",
                "Sessions are merged from 15-minute sleep chunks.")
            add("SLEEP_STAGES", "VENDOR_PROTOCOL",
                "Only raw stage codes are reported; their mapping to light/deep/REM is unverified.")
        }
        return report
    }

    private fun session(
        start: ZonedDateTime,
        minutes: Int,
        stageMinutes: Map<String, Int>,
        isoInstant: DateTimeFormatter,
    ): Map<String, Any?> =
        mapOf(
            "startTime" to isoInstant.format(start.toInstant()),
            "endTime" to isoInstant.format(start.plusMinutes(minutes.toLong()).toInstant()),
            "durationMillis" to (minutes * 60_000L),
            "stageMinutes" to LinkedHashMap(stageMinutes),
            "stageSource" to "FITPRO_RAW",
        )
}
