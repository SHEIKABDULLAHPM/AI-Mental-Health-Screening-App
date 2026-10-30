/*
 * FitPro watch (firmware V15183 family) BLE protocol codec.
 *
 * The FitPro protocol is a vendor protocol used by the "FitPro" OEM app. The
 * facts encoded here (UUIDs, frame layout, byte offsets, command numbers) come
 * from public reverse-engineering documentation and open-source projects:
 *
 *  - Gadgetbridge FitPro protocol notes:
 *    https://gadgetbridge.org/internals/specifics/fitpro-protocol/
 *  - Gadgetbridge FitProDeviceSupport / FitProConstants:
 *    app/src/main/java/nodomain/freeyourgadget/gadgetbridge/
 *      service/devices/fitpro/FitProDeviceSupport.java
 *      devices/fitpro/FitProConstants.java
 *  - MFitX (vanous) LM517CommandInterpreter.kt
 *
 * Nothing here is a copy of that code; it is a clean-room-ish implementation
 * of the documented wire format. The format is UNVERIFIED against a physical
 * FitPro Watch 8 until a real-device validation pass is done — see
 * docs/wearables/verification-matrix.md. Validation should only ever adjust
 * constants in this file; the channel and Dart layers are independent.
 *
 * Frame layout (all multi-byte integers big-endian):
 *
 *    index 0        : header 0xCD
 *    index 1..2     : "full length" = payloadLen + 5
 *    index 3        : command group
 *    index 4        : delimiter / version (0x01)
 *    index 5        : command
 *    index 6..7     : payload length (big-endian)
 *    index 8 .. 8+n : payload
 *
 * Acknowledgment frames (phone -> band) use header 0xDC and the fixed body
 * { 0x00, 0x05, group, 0x01, ackLenHi, ackLenLo, 0x01 } where ackLen =
 * roundTripped "full length" + 3. Two packets with 0xDC header are also
 * "received" from the band during initialization (see Gadgetbridge init log).
 */
package com.mindease.mindease.wearable

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

object FitProProtocol {

    const val HEADER: Int = 0xCD
    const val HEADER_ACK: Int = 0xDC
    const val DELIMITER: Int = 0x01

    /**
     * A UART bridge layout: which service UUID to find, which characteristic
     * carries band->phone notifications, and which receives phone writes.
     */
    class UartVariant(
        val service: UUID,
        val notify: UUID,
        val write: UUID,
    )

    // Nordic-style UART bridge the FitPro band exposes. Two firmware variants
    // exist in the wild with identical base UUIDs except the trailing four
    // characters and with the notify/write rings swapped:
    //   ca9e  canonical Nordic NUS:   notify = 6e400002, write = 6e400003
    //   ca9d  OEM-app/FitPro variant (Gadgetbridge FitProConstants): their
    //         "TX" = 6e400002 is the write characteristic, their "RX" =
    //         6e400003 is the notification characteristic.
    // The channel resolves which variant the device exposes during service
    // discovery instead of assuming one layout.
    val UART_SERVICE_CA9E: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    val UART_RX_CA9E: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    val UART_TX_CA9E: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")

    val UART_SERVICE_CA9D: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9d")
    val UART_RX_CA9D: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9d")
    val UART_TX_CA9D: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9d")

    val UART_VARIANTS: List<UartVariant> = listOf(
        UartVariant(UART_SERVICE_CA9E, UART_RX_CA9E, UART_TX_CA9E),
        UartVariant(UART_SERVICE_CA9D, UART_RX_CA9D, UART_TX_CA9D),
    )

    // Backwards-compatible aliases (canonical Nordic ca9e layout).
    val UART_SERVICE: UUID = UART_SERVICE_CA9E
    val UART_RX: UUID = UART_RX_CA9E
    val UART_TX: UUID = UART_TX_CA9E

    // Standard services also present on FitPro bands.
    val SERVICE_BATTERY: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
    val CHAR_BATTERY_LEVEL: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
    val SERVICE_DEVICE_INFO: UUID = UUID.fromString("0000180a-0000-1000-8000-00805f9b34fb")
    val CHAR_FIRMWARE_REVISION: UUID = UUID.fromString("00002a26-0000-1000-8000-00805f9b34fb")
    val CHAR_MODEL_NUMBER: UUID = UUID.fromString("00002a24-0000-1000-8000-00805f9b34fb")
    val CHAR_MANUFACTURER_NAME: UUID = UUID.fromString("00002a29-0000-1000-8000-00805f9b34fb")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    // Command groups.
    const val GROUP_GENERAL: Int = 0x12
    const val GROUP_BAND_INFO: Int = 0x20
    const val GROUP_RECEIVE_BUTTON_DATA: Int = 0x1c
    const val GROUP_RECEIVE_SPORTS_DATA: Int = 0x15
    const val GROUP_HEART_RATE_SETTINGS: Int = 0x16
    const val GROUP_REQUEST_DATA: Int = 0x1a
    const val GROUP_BIND: Int = 0x14
    const val GROUP_RESET: Int = 0x1d

    // General group commands (0x12).
    const val CMD_SET_DATE_TIME: Int = 0x01
    const val CMD_SET_LANGUAGE: Int = 0x15
    const val CMD_INIT1: Int = 0x0a
    const val CMD_INIT2: Int = 0x0c
    const val CMD_INIT3: Int = 0xff
    /**
     * Real-time heart-rate measurement on/off. Provenance: Gadgetbridge
     * `FitProConstants.CMD_HEART_RATE_MEASUREMENT = 0x18`, sent by
     * `FitProDeviceSupport.onHeartRateTest()` as
     * `craftData(CMD_GROUP_GENERAL, 0x18, VALUE_ON/OFF)` — i.e. a one-byte
     * payload toggling continuous measurement. While enabled the band pushes
     * HR samples as regular group `0x15` / command `0x0e` frames, decoded by
     * [decodeHeartRate].
     */
    const val CMD_HEART_RATE_MEASUREMENT: Int = 0x18

    /** `cd 00 06 12 01 18 00 01 01` (start) / `… 00 00` (stop). */
    fun heartRateMonitorFrame(enabled: Boolean): ByteArray =
        frame(
            GROUP_GENERAL,
            CMD_HEART_RATE_MEASUREMENT,
            byteArrayOf((if (enabled) VALUE_ON else VALUE_OFF).toByte()),
        )

    // Request-data group commands (0x1a).
    const val CMD_GET_STEPS_TARGET: Int = 0x02
    const val CMD_GET_AUTO_HR: Int = 0x08
    const val CMD_GET_CONTACTS: Int = 0x0d
    const val CMD_GET_HW_INFO: Int = 0x10

    // Band-info group commands (0x20).
    const val CMD_RX_BAND_INFO: Int = 0x02

    // Values.
    const val VALUE_ON: Int = 0x01
    const val VALUE_OFF: Int = 0x00
    const val LANG_ENGLISH: Int = 0x01

    // Receive-sports-data group commands (0x15): phone -> band requests…
    const val CMD_REQUEST_STEPS_DATA: Int = 0x06
    /**
     * Sleep-history request. MFitX (`requestSleepHistory`) sends
     * `0x15/0x0d/0x01`; Gadgetbridge's `onFetchRecordedData` only sends the
     * step request, which is why no sleep frame ever arrived in our captures.
     * MFitX also notes the band dislikes this during its 22:00–09:00
     * monitoring window, so the channel only sends it between 10:00 and 21:00.
     */
    const val CMD_REQUEST_SLEEP_DATA: Int = 0x0d
    // …band -> phone payloads.
    const val CMD_RX_STEP_DATA: Int = 0x02
    const val CMD_RX_SLEEP_DATA: Int = 0x03
    const val CMD_RX_DAY_TOTALS: Int = 0x0c
    const val CMD_RX_HEART_RATE: Int = 0x0e
    // These band->phone gates must be ACKed for the band to stream chunks.
    const val CMD_RX_STEP_BURST_GATE_1: Int = 0x07
    const val CMD_RX_STEP_BURST_GATE_2: Int = 0x08
    const val CMD_RX_STEP_BURST_GATE_3: Int = 0x10

    private val CHUNK_SIZE_MILLIS = 5 * 60 * 1000L

    /** Decoded header of an incoming protocol frame. */
    class ParsedFrame(
        val group: Int,
        val command: Int,
        val payload: ByteArray,
        val fullLength: Int,
    ) {
        override fun toString(): String =
            "ParsedFrame(group=0x%02x command=0x%02x payloadLen=%d".format(group, command, payload.size)
    }

    /**
     * Builds a protocol frame to write to the band.
     *
     * Matches the documented examples, e.g.
     *   frame(GROUP_GENERAL, CMD_INIT1, byteArrayOf(0x02))
     *     => cd 00 06 12 01 0a 00 01 02
     *   frame(GROUP_GENERAL, 0x0b, byteArrayOf(0x01))
     *     => cd 00 06 12 01 0b 00 01 01
     */
    fun frame(group: Int, command: Int, payload: ByteArray = byteArrayOf()): ByteArray {
        val out = ByteArray(8 + payload.size)
        out[0] = HEADER.toByte()
        val fullLen = payload.size + 5
        out[1] = ((fullLen shr 8) and 0xff).toByte()
        out[2] = (fullLen and 0xff).toByte()
        out[3] = group.toByte()
        out[4] = DELIMITER.toByte()
        out[5] = command.toByte()
        out[6] = ((payload.size shr 8) and 0xff).toByte()
        out[7] = (payload.size and 0xff).toByte()
        payload.copyInto(out, 8)
        return out
    }

    /**
     * Acknowledgment bytes for an incoming [frame]. Sports/step/sleep/HR
     * frames must be acked or the band withholds the remaining chunks.
     */
    fun ackFor(frame: ParsedFrame): ByteArray {
        val ackLen = frame.fullLength + 3
        return byteArrayOf(
            HEADER_ACK.toByte(),
            0x00,
            0x05,
            frame.group.toByte(),
            DELIMITER.toByte(),
            ((ackLen shr 8) and 0xff).toByte(),
            (ackLen and 0xff).toByte(),
            0x01,
        )
    }

    /** Parses a raw notification into [ParsedFrame], or null if not a valid
     *  0xCD frame. 0xDC (ack) frames and malformed bytes are rejected. */
    fun parse(raw: ByteArray): ParsedFrame? {
        if (raw.size < 8 || raw[0].toInt() and 0xff != HEADER) return null
        val fullLen = ((raw[1].toInt() and 0xff) shl 8) or (raw[2].toInt() and 0xff)
        val plen = ((raw[6].toInt() and 0xff) shl 8) or (raw[7].toInt() and 0xff)
        if (8 + plen > raw.size) return null
        return ParsedFrame(
            group = raw[3].toInt() and 0xff,
            command = raw[5].toInt() and 0xff,
            payload = raw.copyOfRange(8, 8 + plen),
            fullLength = fullLen,
        )
    }

    /**
     * Reassembles protocol frames that arrive split across BLE notifications.
     *
     * The band writes through a UART bridge, and Android delivers at most
     * `MTU - 3` bytes per notification. With the default ATT MTU of 23 that is
     * 20 bytes, while a band-info or step-history frame is longer (the band
     * info frame captured on hardware is 28 bytes: 20 + 8). Treating each
     * notification as a whole frame silently discarded every split frame, so
     * steps and sleep never decoded even when the band sent them.
     *
     * The header's "full length" field is `payload length + 5`, i.e. the total
     * frame length is `fullLen + 3`. Fragments are buffered until that many
     * bytes are available. A stale partial frame is dropped after
     * [staleAfterMillis] so a dropped notification cannot poison the stream
     * forever.
     */
    class FrameAssembler(private val staleAfterMillis: Long = 2_000L) {

        private var buffer: ByteArray = ByteArray(0)
        private var startedAt: Long = 0L

        fun reset() {
            buffer = ByteArray(0)
            startedAt = 0L
        }

        /** Feeds one notification and returns every frame completed by it. */
        fun feed(chunk: ByteArray, nowMillis: Long): List<ParsedFrame> {
            if (chunk.isEmpty()) return emptyList()
            if (buffer.isNotEmpty() && nowMillis - startedAt > staleAfterMillis) {
                reset()
            }
            if (buffer.isEmpty()) {
                val start = chunk.indexOfFirst { (it.toInt() and 0xff) == HEADER }
                if (start < 0) return emptyList()
                buffer = chunk.copyOfRange(start, chunk.size)
                startedAt = nowMillis
            } else {
                val merged = ByteArray(buffer.size + chunk.size)
                buffer.copyInto(merged)
                chunk.copyInto(merged, buffer.size)
                buffer = merged
            }
            val frames = ArrayList<ParsedFrame>()
            while (true) {
                if (buffer.size < 3) break
                if ((buffer[0].toInt() and 0xff) != HEADER) {
                    reset()
                    break
                }
                val fullLen = ((buffer[1].toInt() and 0xff) shl 8) or
                    (buffer[2].toInt() and 0xff)
                val total = fullLen + 3
                // A frame is at least the 8-byte header and cannot be larger
                // than the protocol's payload ceiling. Anything else is noise.
                if (total < 8 || total > 4096) {
                    reset()
                    break
                }
                if (buffer.size < total) break
                parse(buffer.copyOfRange(0, total))?.let { frames.add(it) }
                buffer = buffer.copyOfRange(total, buffer.size)
                if (buffer.isEmpty()) {
                    startedAt = 0L
                    break
                }
                if ((buffer[0].toInt() and 0xff) != HEADER) {
                    reset()
                    break
                }
            }
            return frames
        }
    }

    /**
     * Date encoded in the payload's first two bytes (bits: day 0-4, month 5-8,
     * year 9-15 + 2000).
     */
    fun decodePayloadDate(payload: ByteArray): LocalDate {
        val d = ((payload[0].toInt() and 0xff) shl 8) or (payload[1].toInt() and 0xff)
        val day = d and 0x1f
        val month = (d shr 5) and 0x0f
        val year = (d shr 9) + 2000
        return LocalDate.of(year, month, day)
    }

    /** One heart-rate sample from the band. [timeOfDaySeconds] is the raw
     *  big-endian seconds-of-day field (already seconds, 0..86399). */
    class HeartRateSample(
        val timeOfDaySeconds: Int,
        val heartRate: Int,
        val pressureLow: Int,
        val pressureHigh: Int,
        val spo2: Int,
    )

    /**
     * HR frame (group 0x15, command 0x0e). Offsets mirror the byte positions
     * validated by the Gadgetbridge implementation:
     *   payload[4..7]  seconds-of-day (big-endian int, already seconds —
     *                  do not pass through [secondsOfDay])
     *   payload[5]     SpO2
     *   payload[9]     blood-pressure high
     *   payload[10]    blood-pressure low
     *   payload[11]    heart rate
     * Requires an 8-byte header + 12 payload bytes.
     */
    fun decodeHeartRate(frame: ParsedFrame): HeartRateSample? {
        val p = frame.payload
        if (p.size < 12) return null
        return HeartRateSample(
            timeOfDaySeconds = beInt(p, 4),
            heartRate = p[11].toInt() and 0xff,
            pressureHigh = p[9].toInt() and 0xff,
            pressureLow = p[10].toInt() and 0xff,
            spo2 = p[5].toInt() and 0xff,
        )
    }

    /** One 5-minute step/distance/calorie chunk. */
    class StepChunk(
        val date: LocalDate,
        val minutesOfDay: Int,
        val steps: Int,
        /**
         * The band's low-19-bit field is in calories (thousandths of a kcal),
         * not kcal. Hardware evidence: the verified 423-step day stored
         * 8 kcal (raw ≈ 8000), while reading the field as kcal produced
         * 14,000 kcal for 701 steps on 2026-10-26. Converted once here so no
         * caller can reintroduce the 1000× error.
         */
        val caloriesKcal: Double,
        val distanceMeters: Int,
        val activeMinutes: Int,
        val activityKind: Int,
    )

    /**
     * Step day frame (group 0x15, command 0x02). Payload:
     *   [0..1] date, [2..3] unknown/invariant, then 8-byte chunks:
     *     bits 52-63 steps | 48-51 duration (minutes) | 32-47 distance (m)
     *     | 21-31 minutes-of-day | 19 activity kind | 0-18 calories
     * The minutes-of-day field is a 5-minute index; the Gadgetbridge decoder
     * converts it with index * 15 (getSecondsOfDay), so a full day spans ~96
     * values. The chunk itself covers a 5-minute window.
     */
    fun decodeStepDay(frame: ParsedFrame): List<StepChunk> {
        val p = frame.payload
        if (p.size < 6) return emptyList()
        val date = decodePayloadDate(p)
        val chunks = ArrayList<StepChunk>()
        var i = 4
        while (i + 8 <= p.size) {
            val data = beLong(p, i)
            chunks += StepChunk(
                date = date,
                minutesOfDay = (((data shr 21) and 0x7ff).toInt()) * 15,
                steps = run {
                    val v = (data shr 52) and 0xfff
                    v.toInt()
                },
                caloriesKcal = (data and 0x7ffff).toDouble() / 1000.0,
                distanceMeters = ((data shr 32) and 0xffff).toInt(),
                activeMinutes = ((data shr 48) and 0x0f).toInt(),
                activityKind = ((data shr 19) and 0x01).toInt(),
            )
            i += 8
        }
        return chunks
    }

    /** One 15-minute sleep chunk. */
    class SleepChunk(
        val date: LocalDate,
        val minutesOfDay: Int,
        val kind: Int,
    )

    /**
     * Sleep day frame (group 0x15, command 0x03). Payload:
     *   [0..1] date, then 4-byte chunks with minutes-of-day in the upper
     *   16 bits and sleep kind/flag in the low byte.
     */
    fun decodeSleepDay(frame: ParsedFrame): List<SleepChunk> {
        val p = frame.payload
        if (p.size < 4) return emptyList()
        val date = decodePayloadDate(p)
        val chunks = ArrayList<SleepChunk>()
        var i = 4
        while (i + 4 <= p.size) {
            val data = beInt(p, i)
            chunks += SleepChunk(
                date = date,
                minutesOfDay = (data shr 16) and 0xffff,
                kind = data and 0xff,
            )
            i += 4
        }
        return chunks
    }

    /**
     * Date/time packet sent to synchronize the band's clock before fetching
     * history. Encodes into 4 bytes:
     *   second | (year-2000)<<26 | (month+1)<<22 | day<<17 | hour<<12 | minute<<6
     */
    fun encodeClock(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): ByteArray {
        val zt = now.atZone(zone)
        val encoded =
            zt.second or
                (((zt.year - 2000) and 0x3f) shl 26) or
                ((zt.monthValue and 0x0f) shl 22) or
                ((zt.dayOfMonth and 0x1f) shl 17) or
                ((zt.hour and 0x1f) shl 12) or
                ((zt.minute and 0x3f) shl 6)
        return byteArrayOf(
            ((encoded shr 24) and 0xff).toByte(),
            ((encoded shr 16) and 0xff).toByte(),
            ((encoded shr 8) and 0xff).toByte(),
            (encoded and 0xff).toByte(),
        )
    }

    /** Big-endian unsigned 8-byte read. */
    private fun beLong(bytes: ByteArray, offset: Int): Long {
        var v = 0L
        for (i in 0 until 8) v = (v shl 8) or (bytes[offset + i].toLong() and 0xff)
        return v
    }

    private fun beInt(bytes: ByteArray, offset: Int): Int {
        var v = 0
        for (i in 0 until 4) v = (v shl 8) or (bytes[offset + i].toInt() and 0xff)
        return v
    }

    private fun beShort(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xff) shl 8) or (bytes[offset + 1].toInt() and 0xff)
    }

    /** Seconds-of-day for a minutes-of-day value (sleep chunks, etc.). */
    fun secondsOfDay(minutesOfDay: Int): Int = minutesOfDay * 60
}