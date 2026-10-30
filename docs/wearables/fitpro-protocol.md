# FitPro Watch Protocol (wire format reference)

Status: **PARTIALLY VERIFIED ON HARDWARE (2026-10-26)** — the transport,
initialization handshake, device-info reads, ACK flow and live heart-rate
measurement were exercised against a physical FitPro Watch 8 (firmware
V15183) from the Android app. History streams (steps/sleep/day totals) were
requested but this unit emitted no history frames, so those decoders remain
unit-tested only. See [Live hardware evidence](#live-hardware-evidence-2026-10-26).
This document pins the byte-level facts implemented in
`app/android/app/src/main/kotlin/com/mindease/mindease/wearable/FitProProtocol.kt`
so that a future on-device pass only has to correct constants, never the
channel or Dart layers.

## Sources

Facts are compiled from public reverse-engineering work on the FitPro OEM
protocol (this vendor protocol is used by the "FitPro" app):

- Gadgetbridge FitPro protocol summary —
  https://gadgetbridge.org/internals/specifics/fitpro-protocol/
- Gadgetbridge `FitProDeviceSupport.java` and `FitProConstants.java`:
  `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/fitpro/`
  and `.../devices/fitpro/`
- MFitX (vanous) `LM517CommandInterpreter.kt`

> License note: Gadgetbridge is AGPL-3.0. The implementation is a clean
> wire-format reconstruction, **not** copied code; this doc records the
> observed format facts so the provenance is auditable.

## BLE transport

| Item | Value |
| --- | --- |
| UART service (ca9e variant) | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` (canonical Nordic NUS) |
| TX characteristic (phone → band) | `6e400003-…ca9e` |
| RX characteristic (band → phone, notify) | `6e400002-…ca9e` |
| UART service (ca9d variant) | `6e400001-b5a3-f393-e0a9-e50e24dcca9d` (OEM/FitPro app) |
| TX characteristic (phone → band) | `6e400002-…ca9d` (Gadgetbridge "TX" = write) |
| RX characteristic (band → phone, notify) | `6e400003-…ca9d` (Gadgetbridge "RX" = notify) |
| CCCD | `00002902-0000-1000-8000-00805f9b34fb` |
| Battery service / level | `180F` / `2A19` |
| Device info service | `180A` (`2A26` firmware, `2A24` model, `2A29` manufacturer) |

> Two UART layouts coexist in the wild (identical base UUIDs, trailing 4 chars
> + swapped notify/write rings). The channel resolves whichever variant the
> device advertises during service discovery (`FitProProtocol.UART_VARIANTS`).
> MTU is left at the Android default (23 = 20-byte payload); Gadgetbridge's own
> FitPro support never requests an MTU, so neither do we.

### MTU 247 regression (2026-10-26)

Calling `requestMtu(247)` immediately after `STATE_CONNECTED` and before
`discoverServices()` silently broke the session on this Android stack: the
`discoverServices()` call returned without an `onServicesDiscovered` callback,
the connect watchdog fired after 10 s with `Remote Terminated`, and no history
ever synced. Removing the MTU request made the same steps request stream
succeed. On this band the negotiated MTU stays 23, so notifications are
20-byte fragments; `FitProProtocol.FrameAssembler` buffers them and emits
whole frames. A frame can arrive split across notifications (the band-info
frame does), so parsers must never assume one notification = one frame. The
assembler rejects an oversized/resynchronised buffer instead of guessing.

### Reconnect and read-timeout discipline

Android keeps a dead GATT object looking "connected" after the band sleeps or
walks out of range. `WearableChannel.connect` therefore short-circuits only
when the platform has reported `STATE_CONNECTED` (`gattConnected`), and the
Dart sync path always calls `disconnect()` before a manual/scheduled
reconnect. `readSnapshot` refuses a link that is not `gattConnected`.
Standard GATT reads are serialized with a 2.5 s timeout so one unanswered
read cannot hold the snapshot until the watchdog (30 s); a late callback for
an already-timed-out read is ignored.

## Frame layout

All multi-byte integers are big-endian.

### Phone → band (`0xCD`)

```
index 0        : header 0xCD
index 1..2     : "full length" = payloadLen + 5
index 3        : command group
index 4        : delimiter / version (0x01)
index 5        : command
index 6..7     : payload length (BE)
index 8 .. 8+n : payload
```

Examples from the Gadgetbridge source log:

```
cd 00 06 12 01 0a 00 01 02      # general / INIT1, payload [0x02]
cd 00 06 12 01 0b 00 01 01      # general / find-band, payload [0x01]
cd 00 09 12 01 01 00 04 a5 83 73 db   # general / set-time  (4-byte clock)
```

### Band acknowledgment (`0xDC`)

```
dc 00 05 <group> 01 <ackLenHi> <ackLenLo> 01
```

where `ackLen = roundtrippedFullLength + 3`. The band sends two `0xDC`
packets during initialization as well.

## Command groups / commands

| Group | Value | Group | Value |
| --- | --- | --- | --- |
| GENERAL | `0x12` | BAND_INFO | `0x20` |
| RECEIVE_SPORTS_DATA | `0x15` | RequestData | `0x1a` |

| Command | Value | Meaning |
| --- | --- | --- |
| SET_DATE_TIME | `0x01` (general) | sync band clock |
| SET_LANGUAGE | `0x15` | — |
| INIT1 | `0x0a` | init handshake (payload `0x02`) |
| INIT2 | `0x0c` / `0xff` | init handshake continuation |
| HEART_RATE_MEASUREMENT | `0x18` (general) | live measurement on/off (payload `0x01` / `0x00`) |
| GET_HW_INFO | `0x10` (request-data) | hw info |
| REQUEST_STEPS_DATA | `0x06` (sports-data) | start history stream, payload `0x01` |
| RX_STEP_DATA | `0x02` | band → phone step day frame |
| RX_SLEEP_DATA | `0x03` | band → phone sleep day frame |
| RX_DAY_TOTALS | `0x0c` | band → phone day summary |
| RX_HEART_RATE | `0x0e` | band → phone HR sample |
| gates | `0x07`, `0x08`, `0x10` | must be ACKed to continue streaming |

## Payload decodes

Offsets below are relative to the payload (frame index 8).

### Heart rate (group `0x15`, command `0x0e`)

```
payload[4..7]  seconds-of-day (BE int, already seconds; 0..86399)
payload[5]     SpO2
payload[9]     blood-pressure high
payload[10]    blood-pressure low
payload[11]    heart rate (bpm)
```

Requires ≥ 12 payload bytes. Reference frame:
`cd 00 11 15 01 0e 00 0c 2b 04 00 01 00 01 43 94 62 5c 48 53`
→ hr 83, BP 92/72, SpO2 1, seconds-of-day `0x00014394` (23:00:36).

Live frame captured from the real watch over the app's GATT session:

```
cd 00 11 15 01 0e 00 0c 35 5a 00 01 00 01 1e 74 61 54 7a 4e
```

→ heart rate `0x4e` = **78 bpm**, seconds-of-day `0x00011e74` = 73332
(20:22:12 local, matching the clock the app had just written). The app stored
it as `HEART_RATE / 78 / bpm / DEVICE_MEASURED` under the registered device.
A second session produced `... 00 01 1c b6 ... 4b` → 75 bpm.

### Live heart-rate measurement (group `0x12`, command `0x18`)

Provenance: Gadgetbridge `FitProConstants.CMD_HEART_RATE_MEASUREMENT = 0x18`
(`CMD_GROUP_GENERAL = 0x12`), sent by `onHeartRateTest()` with a one-byte
on/off payload. The band acknowledges the command, then pushes group `0x15` /
command `0x0e` samples roughly every 10 s while measurement is on:

```
cd 00 06 12 01 18 00 01 01   # measurement on  (verified)
cd 00 06 12 01 18 00 01 00   # measurement off (verified)
```

The app paces `INIT1` → clock sync → measurement-on, because the band ignores
the toggle on a fresh, unsynchronised link. `true` from
`startHeartRateMonitor` means the sequence left the radio; samples are only
reported if the band actually sends them, and zero bpm is discarded as a
placeholder.

> **Android notification requirement (found live):** writing the CCCD
> (`2902` → `01 00`) is not sufficient. The GATT client must also call
> `setCharacteristicNotification(rx, true)`; without it the band ACKs into a
> void and `onCharacteristicChanged` never fires. This looked like a dead band
> until both steps were performed.

### Step day (group `0x15`, command `0x02`)

```
[0..1] date (see below)
[2..3] unknown / invariant
[4..]  repeated 8-byte chunks:
  bits 52-63  steps
  bits 48-51  active duration (minutes)
  bits 32-47  distance (meters)
  bits 21-31  5-minute index  (minutes-of-day = index * 15)
  bits 19     activity kind
  bits 0-18   calories (thousandths of a kcal; divide by 1000)
```

**Calorie unit (fixed 2026-10-27).** The low 19-bit field is not kcal. A
captured chunk on 2026-10-26 held `0x0a28` = 2600 for 128 steps / 89 m,
i.e. 2.6 kcal. The earlier verified row (423 steps / 346 m / 8 kcal) matches
the same 1/1000 scale. Storing the raw value as kcal produced
**14,000 kcal for 701 steps**, so `FitProProtocol` now converts once at decode
time and the rollup sums kcal.

### Sleep day (group `0x15`, command `0x03`)

```
[0..1] date
[4..]  repeated 4-byte chunks:
  high 16 bits  minutes-of-day  (minutes, not a 5-min index)
  low byte      sleep kind
```

### Day totals (group `0x15`, command `0x0c`) — do not use

```
[2..5]   steps (BE int)
[6..9]   distance (BE int, meters)
[10..11] calories (BE short)
```

The layout above is what the vendor/Gadgetbridge code suggests, but **no
consistent frame has been observed on V15183**. Captures from two connections
decoded to `1 step / 3.3e9 m` and `115,996 steps / 81,247 m` for the same
afternoon. Gadgetbridge ACKs the frame and leaves its
`handleDayTotalsData(steps, distance, calories)` call commented out. Synora
therefore ACKs `0x0c` (so the band keeps streaming) but never turns it into a
reading or a daily total. Step chunks are the only activity source.

### History is a one-shot delta

The band sends each history chunk **once and then deletes it**. Every fetch is
therefore a delta since the previous sync, not a fresh copy of the day. The
client marks daily rows `INTERVAL_DELTA` and the backend adds them to the
stored day; replacing would silently drop earlier steps (423 stored at 19:34,
next fetch's 701-step delta overwrote it). Sync retries are idempotent because
the backend echoes the stored result for a repeated `clientSyncId`.

### Date field (payload `[0..1]`)

```
bits 0-4   day
bits 5-8   month
bits 9-15  year − 2000
```

e.g. `0x3546` → day 6, month 10, year 2026.

### Clock packet (SET_DATE_TIME payload, 4 bytes)

```
second | (year-2000) << 26 | (month+1) << 22 | day << 17 | hour << 12 | minute << 6
```

## Initialization / history-fetch sequence (phone → band)

Paced ~200 ms apart (from the Gadgetbridge init log; the band must process
each command before the next):

1. `0x12` / `0x0a` (`INIT1`) payload `0x02`
2. `0x12` / `0x01` clock packet
3. `0x1a` / `0x0a`, `0x1a` / `0x0c`, `0x1a` / `0x01`, `0x1a` / `0x0f`,
   `0x1a` / `0x10`
4. `0x15` / `0x06` payload `0x01` (start step stream)

Every incoming sports-data / band-info / request-data frame is answered with
its `0xDC` ACK (`ackLen = fullLength + 3`); gates `0x07`/`0x08`/`0x10` must be
ACKed or the band withholds the remaining chunks.

## What Synora does not use (Phase 1)

- Structured workout sessions: not exposed in this slice of the protocol; the
  snapshot reports an empty `exerciseSessions` list rather than fabricating
  data.
- Sleep stage kinds are preserved raw (`kind` byte) but not interpreted.

## Live hardware evidence (2026-10-26)

Device: FitPro Watch 8, public address `6D:7D:64:37:03:28`, firmware `V15183`,
hardware `01`, serial `10000001`, model string `MI RC`, SOFTWARE
`001000010111011`, battery 54 %. (A second product sharing the same marketing
name has address `3A:4B:5D:58:03:28`; it is not this device.)

GATT services enumerated live:
`1800`, `1801`, `180A`, `180F`, `6e400001-…ca9d`, `FFFF`, `1812`, `FFFA`.
The UART variant resolved to the `…ca9d` layout (write `…02`, notify `…03`).
No ECG service, and no ECG command exists in this protocol slice.

Initialization captured through the app's own channel (phone → band, paced
200 ms, with the band's replies):

```
TX cd 00 06 12 01 0a 00 01 02
RX dc 00 05 12 0a 00 09 01
TX cd 00 09 12 01 01 00 04 6a b5 43 98
RX dc 00 05 12 01 00 0c 01
TX cd 00 05 1a 01 0a 00 00
RX dc 00 05 1a 0a 00 08 01
RX cd 00 0b 1a 01 0a 00 06 3a 4b 5d 58 03 28
TX cd 00 05 1a 01 0c 00 00
RX dc 00 05 1a 0c 00 08 01
TX cd 00 06 12 01 15 00 01 01
RX dc 00 05 12 15 00 09 01
TX cd 00 06 12 01 ff 00 01 01
RX dc 00 05 12 ff 00 09 01
TX cd 00 05 1a 01 01 00 00
RX cd 00 09 1a 01 01 00 04 99 55 08 21
TX cd 00 05 1a 01 0f 00 00
RX dc 00 05 1a 0f 00 08 01
TX cd 00 05 1a 01 10 00 00
RX dc 00 05 1a 10 00 08 01
TX cd 00 05 20 01 02 00 00
RX cd 00 19 20 01 02 00 14 00 00 00 80 00 80 05 4c 59 37 32 38 05 4c 59 37 32 38 00 02
TX cd 00 06 15 01 06 00 01 01
```

The band answers each command with its `0xDC` receipt ACK. After the
notification-registration fix described above, this stream is reproducible on
every connection; before it, the phone received nothing at all while a host
`gatttool` session received the same ACKs.

Live measurement, captured from the app:

```
TX cd 00 06 12 01 0a 00 01 02
TX cd 00 09 12 01 01 00 04 6a b5 45 82
TX cd 00 06 12 01 18 00 01 01
RX dc 00 05 12 18 00 09 01
RX cd 00 07 1c 01 08 00 02 00 00
RX cd 00 11 15 01 0e 00 0c 35 5a 00 01 00 01 1e 74 61 54 7a 4e
```

The app decoded 78 bpm, showed it on the Heart rate monitor screen, persisted
it on Stop, uploaded it to `/physical/sync` and stored
`HEART_RATE=78 bpm, DEVICE_MEASURED, source=FITPRO` under device
`6addcbd88b3ebd0247fbe8d9`. A second run produced 75 bpm the same way.

### Real step history (2026-10-26)

After the MTU/discovery fix, the same step request (`0x15` / `0x06`, payload
`0x01`) returned real group `0x15` step frames. The app assembled them into
one row per band-local date and stored **423 steps, 346 m, 8 kcal** for
2026-10-26; the dashboard rendered "423 steps / 0.35 km / 8 kcal" and the
weekly trend chart filled in. This confirms the step-offset decoder on
hardware, not only in unit tests.

A later fresh reconnect on 2026-10-27 completed the full preamble and
answered every command, but emitted no step frames that session. The request
path is confirmed; whether the band had no new intervals for the new day or
withholds unchanged history is not established from that capture.

```
TX cd 00 06 12 01 0a 00 01 02
RX dc 00 05 12 0a 00 09 01
...
TX cd 00 06 15 01 06 00 01 01
RX dc 00 05 1a 00 00 08 01
```

### SpO2 provenance

The blood-oxygen byte is `payload[5]` (`value[13]` of the full frame), the same
offset Gadgetbridge passes to `setSpo2Percent`. Synora now emits it as a
`SPO2` reading **only** when it is in the plausible 50–100 % range; `0` (no
measurement) and out-of-range noise stay unemitted. This means SpO2 is
"supported by the frame format" even before a particular session produces a
measurable sample — the capability stays `UNKNOWN` until a real record is
stored, then the server promotes it from evidence.

### Still unverified on hardware

- Sleep: the separate `0x15`/`0x0d`/`0x01` request (MFitX
  `requestSleepHistory`, only sent 10:00-21:00) was sent on 2026-10-27 and the
  band ACKed it (`dc 00 05 15 0d 00 09 01`), but **no `0x15`/`0x03` frame has
  ever arrived** — not even after the request. The decoder and capability path
  are unit-tested, but no sleep record is claimed. If the band only replays
  sleep when a session exists, an empty result is the honest outcome; the
  fetch window is 8 s plus up to three 4 s extensions for late frames.
- HRV: the FitPro frame layout has no HRV field (Gadgetbridge decodes none),
  so it stays `UNSUPPORTED` rather than being inferred from RR intervals.
- The `0x15` / `0x1c` frames observed while measuring are not decoded (their
  meaning is not needed for heart rate).

## Validation checklist

1. ✅ Connect a real FitPro Watch 8 (firmware V15183 family) — done
   (2026-10-26).
2. ✅ Capture raw notifications and diff against the reference byte layouts —
   done for init, ACKs, device info and live heart rate.
3. ✅ History decoder on hardware (steps): **423 steps / 346 m / 8 kcal** for
   2026-10-26 decoded from real `0x15`/`0x02` frames and rendered. Later
   deltas summed to 701 steps / 484 m / 14 kcal for that day (the earlier 423
   row had already been lost from the database; the band deletes sent
   history, so it cannot be re-fetched). Calories were corrected from raw
   thousandths-of-a-kcal on 2026-10-27. If a decode is off by a known
   constant, change only `FitProProtocol.kt`, update `FitProProtocolTest.kt`
   vectors, and re-run `./gradlew :app:testDebugUnitTest`.
4. ⬜ Confirm the clock write advances the band display time (the app writes
   the packet and the band's HR seconds-of-day matched the host clock, but the
   physical dial was not photographed).
5. ✅ Live heart-rate measurement on/off (`0x18`) and sample decode
   (`0x15`/`0x0e`) — 78 bpm and 75 bpm captured and persisted.
6. ✅ ECG absence: no ECG service/command on this device; the app shows an
   explicit unsupported state instead of a waveform.

See `docs/wearables/verification-matrix.md` for the tracking table.