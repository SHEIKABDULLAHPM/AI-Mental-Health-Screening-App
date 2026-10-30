/*
 * Unit tests for the FitPro wire codec. These pin the codec to the frames
 * documented by open-source FitPro reverse engineering (see FitProProtocol
 * header for sources) so a hardware-validation pass only ever has to fix
 * constants in FitProProtocol, never the channel or Dart layers.
 */
package com.mindease.mindease.wearable

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class FitProProtocolTest {

    private fun hex(vararg bytes: Int): ByteArray = ByteArray(bytes.size) { bytes[it].toByte() }

    private fun hexString(bytes: ByteArray): String =
        bytes.joinToString(" ") { "%02x".format(it.toInt() and 0xff) }

    @Test
    fun frame_matchesDocumentedInitializationPacket() {
        val frame = FitProProtocol.frame(
            FitProProtocol.GROUP_GENERAL,
            FitProProtocol.CMD_INIT1,
            byteArrayOf(0x02),
        )
        assertEquals("cd 00 06 12 01 0a 00 01 02", hexString(frame))
    }

    @Test
    fun frame_matchesDocumentedFindBandPacket() {
        val frame = FitProProtocol.frame(
            FitProProtocol.GROUP_GENERAL,
            0x0b,
            byteArrayOf(0x01),
        )
        assertEquals("cd 00 06 12 01 0b 00 01 01", hexString(frame))
    }

    @Test
    fun frame_matchesDocumentedStepsHistoryRequest() {
        // Gadgetbridge FitProDeviceSupport: CMD_REQUEST_STEPS_DATA1 with ON.
        val frame = FitProProtocol.frame(
            FitProProtocol.GROUP_RECEIVE_SPORTS_DATA,
            FitProProtocol.CMD_REQUEST_STEPS_DATA,
            byteArrayOf(FitProProtocol.VALUE_ON.toByte()),
        )
        assertEquals("cd 00 06 15 01 06 00 01 01", hexString(frame))
    }

    @Test
    fun frame_matchesMfitxSleepHistoryRequest() {
        // MFitX LM517CommandInterpreter.requestSleepHistory posts exactly
        // cd:00:06:15:01:0d:00:01:01, only between 10:00 and 21:00.
        val frame = FitProProtocol.frame(
            FitProProtocol.GROUP_RECEIVE_SPORTS_DATA,
            FitProProtocol.CMD_REQUEST_SLEEP_DATA,
            byteArrayOf(FitProProtocol.VALUE_ON.toByte()),
        )
        assertEquals("cd 00 06 15 01 0d 00 01 01", hexString(frame))
    }

    @Test
    fun frame_withoutPayloadMatchesDocumentedPacket() {
        val frame = FitProProtocol.frame(FitProProtocol.GROUP_REQUEST_DATA, 0x0f)
        assertEquals("cd 00 05 1a 01 0f 00 00", hexString(frame))
    }

    @Test
    fun frame_withTimePayloadMatchesDocumentedLengthBytes() {
        val frame = FitProProtocol.frame(
            FitProProtocol.GROUP_GENERAL,
            FitProProtocol.CMD_SET_DATE_TIME,
            FitProProtocol.encodeClock(
                LocalDate.of(2026, 10, 6).atTime(7, 8, 9).atZone(java.time.ZoneId.of("UTC")).toInstant(),
                java.time.ZoneId.of("UTC"),
            ),
        )
        assertEquals(12, frame.size)
        assertEquals("cd 00 09 12 01 01 00 04", hexString(frame.copyOfRange(0, 8)))
    }

    @Test
    fun parse_acceptsDocumentedHeartRateFrame() {
        val raw = hex(
            0xcd, 0x00, 0x11, 0x15, 0x01, 0x0e, 0x00, 0x0c,
            0x2a, 0xf8, 0x00, 0x01, 0x00, 0x00, 0x31, 0x2c,
            0x62, 0x75, 0x54, 0x47,
        )
        val frame = FitProProtocol.parse(raw)
        assertNotNull(frame)
        assertEquals(0x15, frame!!.group)
        assertEquals(0x0e, frame.command)
        assertEquals(12, frame.payload.size)
    }

    @Test
    fun parse_rejectsAckFramesAndGarbage() {
        val ack = hex(0xdc, 0x00, 0x05, 0x1a, 0x01, 0x00, 0x08, 0x01)
        assertNull(FitProProtocol.parse(ack))
        assertNull(FitProProtocol.parse(hex(0xab, 0x00, 0x00)))
        assertNull(FitProProtocol.parse(byteArrayOf()))
    }

    @Test
    fun parse_rejectsPayloadLengthOverflow() {
        // payload length claims 12 bytes but only 4 are present.
        val raw = hex(0xcd, 0x00, 0x11, 0x15, 0x01, 0x0e, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00)
        assertNull(FitProProtocol.parse(raw))
    }

    @Test
    fun decodeHeartRateExtractsDocumentedOffsets() {
        // Second documented HR frame: heartbeat 0x48=72.
        val raw = hex(
            0xcd, 0x00, 0x11, 0x15, 0x01, 0x0e, 0x00, 0x0c,
            0x2b, 0x04, 0x00, 0x01, 0x00, 0x01, 0x43, 0x94,
            0x62, 0x5c, 0x48, 0x53,
        )
        val hr = FitProProtocol.decodeHeartRate(FitProProtocol.parse(raw)!!)!!
        assertEquals(0x53, hr.heartRate) // 83
        assertEquals(0x5c, hr.pressureHigh)
        assertEquals(0x48, hr.pressureLow)
        assertEquals(0x0001_4394, hr.timeOfDaySeconds) // 23:00:36, already seconds
        assertEquals(0x01, hr.spo2)
    }

    @Test
    fun decodeHeartRateRequiresFullPayload() {
        val frame = FitProProtocol.frame(FitProProtocol.GROUP_RECEIVE_SPORTS_DATA, 0x0e, byteArrayOf(0, 1, 2))
        assertNull(FitProProtocol.decodeHeartRate(FitProProtocol.parse(frame)!!))
    }


    @Test
    fun decodeStepDayParses8ByteChunks() {
        val date = LocalDate.of(2026, 10, 6)
        // encodedTime index 34 -> minutesOfDay 34 * 15 = 510 -> 08:30.
        val chunk: Long =
            (1000L shl 52) or
                (5L shl 48) or
                (750L shl 32) or
                (34L shl 21) or
                (0L shl 19) or
                50L
        val payload = byteArrayOf(0x35, 0x46, 0x00, 0x00) + beBytes8(chunk)
        val frame = FitProProtocol.frame(FitProProtocol.GROUP_RECEIVE_SPORTS_DATA, 0x02, payload)

        val chunks = FitProProtocol.decodeStepDay(FitProProtocol.parse(frame)!!)
        assertEquals(1, chunks.size)
        val c = chunks.first()
        assertEquals(date, c.date)
        assertEquals(510, c.minutesOfDay) // 08:30
        assertEquals(1000, c.steps)
        assertEquals(750, c.distanceMeters)
        assertEquals(5, c.activeMinutes)
        assertEquals(0.05, c.caloriesKcal, 1e-9)
        assertEquals(0, c.activityKind)
    }

    @Test
    fun decodeStepDayConvertsHardwareCaloriesToKcal() {
        // Captured from the real Watch 8 on 2026-10-26: raw calories 2600
        // (0x0a28) for 128 steps / 89 m. Stored as kcal that is 2.6 kcal;
        // treating the field as kcal produced 14,000 kcal per day.
        val payload = hex(
            0x35, 0x5a, 0x00, 0x01,
            0x08, 0x00, 0x00, 0x59, 0x0a, 0x08, 0x0a, 0x28,
        )
        val frame = FitProProtocol.frame(FitProProtocol.GROUP_RECEIVE_SPORTS_DATA, 0x02, payload)
        val chunk = FitProProtocol.decodeStepDay(FitProProtocol.parse(frame)!!).single()
        assertEquals(LocalDate.of(2026, 10, 26), chunk.date)
        assertEquals(128, chunk.steps)
        assertEquals(89, chunk.distanceMeters)
        assertEquals(2.6, chunk.caloriesKcal, 1e-9)
    }


    @Test
    fun decodeSleepDayParses4ByteChunks() {
        // 525 minutes (08:45) with sleep kind 2 in the low byte. Chunks run
        // from payload offset 4 (2 date bytes + 2 unknown bytes, mirroring the
        // full-frame offset 12 used by Gadgetbridge).
        val data: Int = (525 shl 16) or 2
        val payload = byteArrayOf(
            0x35, 0x46, 0x00, 0x00,
            (data shr 24).toByte(), (data shr 16).toByte(), (data shr 8).toByte(), data.toByte(),
        )
        val frame = FitProProtocol.frame(FitProProtocol.GROUP_RECEIVE_SPORTS_DATA, 0x03, payload)

        val chunks = FitProProtocol.decodeSleepDay(FitProProtocol.parse(frame)!!)
        assertEquals(1, chunks.size)
        val c = chunks.first()
        assertEquals(LocalDate.of(2026, 10, 6), c.date)
        assertEquals(525, c.minutesOfDay)
        assertEquals(2, c.kind)
    }

    @Test
    fun payloadDateRoundTripsThroughBits() {
        assertEquals(LocalDate.of(2026, 10, 6), FitProProtocol.decodePayloadDate(byteArrayOf(0x35, 0x46)))
        // 2024-12-31 -> (24 << 9) | (12 << 5) | 31 = 0x319F.
        assertEquals(LocalDate.of(2024, 12, 31), FitProProtocol.decodePayloadDate(byteArrayOf(0x31, (-0x61).toByte())))
    }

    @Test
    fun ackFrameRoundTripsFullLength() {
        val raw = hex(
            0xcd, 0x00, 0x11, 0x15, 0x01, 0x0e, 0x00, 0x0c,
            0x2a, 0xf8, 0x00, 0x01, 0x00, 0x00, 0x31, 0x2c,
            0x62, 0x75, 0x54, 0x47,
        )
        val frame = FitProProtocol.parse(raw)!!
        // fullLength 0x11 + 3 = 0x14.
        assertEquals("dc 00 05 15 01 00 14 01", hexString(FitProProtocol.ackFor(frame)))
    }

    @Test
    fun secondsOfDayConvertsMinutes() {
        assertEquals(510 * 60, FitProProtocol.secondsOfDay(510)) // 08:30
        assertEquals(525 * 60, FitProProtocol.secondsOfDay(525)) // 08:45
        assertEquals(0, FitProProtocol.secondsOfDay(0))
    }

    @Test
    fun encodeClockIsFourBytesBigEndian() {
        val zone = java.time.ZoneId.of("UTC")
        val instant = LocalDate.of(2026, 10, 6).atTime(7, 8, 9).atZone(zone).toInstant()
        val bytes = FitProProtocol.encodeClock(instant, zone)
        assertEquals(4, bytes.size)
        val decoded: Int = (((bytes[0].toInt() and 0xff) shl 24) or
            ((bytes[1].toInt() and 0xff) shl 16) or
            ((bytes[2].toInt() and 0xff) shl 8) or
            (bytes[3].toInt() and 0xff))
        assertEquals(9, decoded and 0x3f) // seconds
        assertEquals(7, (decoded shr 12) and 0x1f) // hour
        assertEquals(8, (decoded shr 6) and 0x3f) // minute
        assertEquals(6, (decoded shr 17) and 0x1f) // day
    }

    @Test
    fun heartRateMonitorFramesToggleMeasurement() {
        // Provenance: Gadgetbridge FitProConstants.CMD_HEART_RATE_MEASUREMENT
        // (0x18) in CMD_GROUP_GENERAL (0x12), one-byte on/off payload.
        assertEquals(
            "cd 00 06 12 01 18 00 01 01",
            hexString(FitProProtocol.heartRateMonitorFrame(true)),
        )
        assertEquals(
            "cd 00 06 12 01 18 00 01 00",
            hexString(FitProProtocol.heartRateMonitorFrame(false)),
        )
    }

    @Test
    fun uartVariantsCoverBothLayouts() {
        val ca9e = FitProProtocol.UART_VARIANTS.first {
            it.service == FitProProtocol.UART_SERVICE_CA9E
        }
        assertEquals(FitProProtocol.UART_RX_CA9E, ca9e.notify)
        assertEquals(FitProProtocol.UART_TX_CA9E, ca9e.write)

        val ca9d = FitProProtocol.UART_VARIANTS.first {
            it.service == FitProProtocol.UART_SERVICE_CA9D
        }
        // Gadgetbridge FitProConstants: "TX" (write) = 0002, "RX" (notify) = 0003.
        assertEquals("6e400003-b5a3-f393-e0a9-e50e24dcca9d", ca9d.notify.toString())
        assertEquals("6e400002-b5a3-f393-e0a9-e50e24dcca9d", ca9d.write.toString())
    }

    @Test
    fun frameAssembler_reassemblesFrameSplitAcrossNotifications() {
        // Hardware capture: the 28-byte band-info frame arrived as 20 + 8
        // bytes with the default ATT MTU. Dropping either part loses the frame.
        val frame = FitProProtocol.frame(
            FitProProtocol.GROUP_BAND_INFO,
            FitProProtocol.CMD_RX_BAND_INFO,
            ByteArray(20) { it.toByte() },
        )
        assertEquals(28, frame.size)
        val assembler = FitProProtocol.FrameAssembler()
        assertTrue(assembler.feed(frame.copyOfRange(0, 20), 1_000L).isEmpty())
        val parsed = assembler.feed(frame.copyOfRange(20, 28), 1_100L)
        assertEquals(1, parsed.size)
        assertEquals(FitProProtocol.GROUP_BAND_INFO, parsed[0].group)
        assertEquals(FitProProtocol.CMD_RX_BAND_INFO, parsed[0].command)
        assertEquals(20, parsed[0].payload.size)
    }

    @Test
    fun frameAssembler_handlesBackToBackFramesInOneNotification() {
        val a = FitProProtocol.frame(
            FitProProtocol.GROUP_RECEIVE_SPORTS_DATA,
            FitProProtocol.CMD_RX_STEP_DATA,
            ByteArray(4),
        )
        val b = FitProProtocol.frame(
            FitProProtocol.GROUP_RECEIVE_SPORTS_DATA,
            FitProProtocol.CMD_RX_DAY_TOTALS,
            ByteArray(12),
        )
        val parsed = FitProProtocol.FrameAssembler().feed(a + b, 1_000L)
        assertEquals(2, parsed.size)
        assertEquals(FitProProtocol.CMD_RX_STEP_DATA, parsed[0].command)
        assertEquals(FitProProtocol.CMD_RX_DAY_TOTALS, parsed[1].command)
    }

    @Test
    fun frameAssembler_dropsStalePartialFrameBeforeNewFrame() {
        val frame = FitProProtocol.frame(
            FitProProtocol.GROUP_BAND_INFO,
            FitProProtocol.CMD_RX_BAND_INFO,
            ByteArray(20),
        )
        val assembler = FitProProtocol.FrameAssembler(staleAfterMillis = 1_000L)
        assertTrue(assembler.feed(frame.copyOfRange(0, 10), 1_000L).isEmpty())
        // More than the stale window later, a complete new frame must not be
        // glued onto the abandoned partial one.
        val parsed = assembler.feed(frame, 5_000L)
        assertEquals(1, parsed.size)
        assertEquals(20, parsed[0].payload.size)
    }

    private fun beBytes8(v: Long): ByteArray = ByteArray(8) { ((v shr (56 - it * 8)) and 0xffL).toByte() }
}