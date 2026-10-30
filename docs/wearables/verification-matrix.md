# Physical wellness verification matrix

Feature: **Synora Physical Wellness ecosystem** — wearable foundation
(Phase 1), lifestyle tracking (Phase 2), advanced metrics + capability
registry (Phase 3), and the Mind–Body pattern engine (Phase 4).

Legend: ✅ verified · 🟡 needs real hardware · ⬜ not started

Environment used for the checks below:

- Backend + AI service: Docker Compose stack on the dev host
  (`mindease-backend`, `mindease-ai-service`), host `192.168.1.4`.
- Phone: Samsung SM-M325F, Android, user 0, connected over wireless debugging
  at `192.168.1.2:37837` for the 2026-10-26 pass; debug APK built with
  `API_BASE_URL=http://192.168.1.4:8080/api/v1` and
  `AUTH_SERVER_URL=http://192.168.1.4:8083`. On 2026-10-27 the phone moved to
  `:39245` and then stopped accepting adb entirely (no mDNS, ports closed), so
  later UI was verified by widget/route tests only.
- **Real FitPro Watch 8** (firmware `V15183`, public address
  `6D:7D:64:37:03:28`) connected through the app for the 2026-10-26 pass.
  A second product with the same marketing name
  (`3A:4B:5D:58:03:28`) is not this device and was ignored.
- Results below marked ✅ are backed by observed frames/logcat/Mongo records;
  rows marked 🟡 still have no on-hardware evidence.

## Layer map

| # | Layer | Where | Test evidence | Status |
| --- | --- | --- | --- | --- |
| 1 | Protocol codec (Kotlin) | `android/.../wearable/FitProProtocol.kt` | `FitProProtocolTest` — 21 unit tests: frame craft, ACK round-trip, fragment reassembly, HR/step/sleep/day-total decode offsets, date & clock encode/decode, live HR measurement on/off (`0x12`/`0x18`), overflow/parse rejection | ✅ (unit) · ✅ init/ACK/HR/step bytes matched live frames |
| 2 | BLE channel | `android/.../wearable/WearableChannel.kt` + `MainActivity.kt` wiring | `:app:testDebugUnitTest` green (41 tests); pre-33 GATT write path, both notification overloads, serialized preamble/ACK writes, malformed-address rejection, unknown-frame receipt ACK, MTU-23 frame reassembly, read timeout, forced reconnect | ✅ (build+unit) · ✅ live GATT/notifications/ACKs/steps |
| 3 | Snapshot assembly | `android/.../wearable/SnapshotAssembler.kt` | `SnapshotAssemblerTest` — 18 unit tests: stage-minute accumulation, raw stage labels (`RAW_<n>`), capability report construction, SpO2 range filtering, unsupported metrics omitted rather than faked | ✅ (unit) · ✅ step rollup on hardware · 🟡 sleep frames never arrived |
| 4 | Manifest / permissions | `android/app/src/main/AndroidManifest.xml` | Manifest merge + `assembleDebug` succeed; APK installs, launches and scans/connects over BLE on the physical phone | ✅ (merge+launch+BLE grant) |
| 5 | Dart gateway | `app/lib/features/physical_wellness/data/wearable_gateway.dart` | Missing plugin degrades safely; platform errors surface as typed `WearableException`; `bluetoothState()` reports on/off/unsupported; watch-name compatibility filter; live HR `EventChannel` stream is re-created per call (Restart-safe) | ✅ (unit) · ✅ end-to-end |
| 6 | Controllers / cache | `.../presentation/state/` + `physical_local_cache.dart` | Flutter suite: **345 passed, 1 skipped** (controller/cache/queue tests + automatic-refresh + periodic sync-if-stale + live-HR/SpO2 + stale-batch recovery tests); no optimistic "saved" state for offline writes | ✅ |
| 7 | UI / routing / audit | all 25 routes × 3 text-scale configs | `feature_audit_test` + full `flutter test`: **345 passed, 1 skipped, 0 failed**; `/physical-wellness` paints clean; HR/ECG screens covered by widget tests | ✅ |
| 8 | Backend lifestyle API | `features/physical` controllers/services/DTOs | `mvn test`: **547 passed, 0 failed** (inclusive Mongo range contract, unit-aware validation, capability downgrade, sync idempotency, upsert race merge, wake-date sleep windows, measured-HR visibility) | ✅ |
| 9 | Capability registry | `DeviceCapabilityService` + Mongo `device_capabilities` | 9 service tests + live API: seeded on registration, client cannot self-certify, FitPro-unsupported metrics forced to `UNSUPPORTED` | ✅ (API + unit) · 🟡 on-device sensor claims |
| 10 | Mind–Body pattern engine | `MindBodyPatternEngine` + `PhysicalInsightService` + AI client | Backend tests + live API: deterministic rules, explicit provenance, AI failure falls back to rule wording, weight excluded from inference | ✅ (API + unit) |
| 11 | AI wording service | `ai-service/app/core/wellness/physical_insights.py`, `/wellness/insights` | AI suite **133 passed**; container rebuilt and imports the wellness module | ✅ |
| 12 | Live end-to-end API | `/tmp/opencode/e2e_lifestyle.py` (74 checks) | registration → device → capabilities → hydration → body/BMI → goals → trends → insights → sync (sleep stages) → ownership isolation | ✅ 74/74 |

## Real-device UI checks (physical phone, live backend)

Observed on the installed debug APK on the SM-M325F, not an emulator:

| Check | Observed | Status |
| --- | --- | --- |
| App launch | Splash → dashboard, no `E/flutter`, no `FATAL` in logcat | ✅ |
| Physical Wellness route | Dashboard card opens the screen; header renders | ✅ |
| Device card | Registered device shown with sync state ("5 batches waiting to upload") and Connect another control | ✅ |
| Unsupported activity | "Your watch does not track steps." / "Not tracked" / active-minutes explanation — no fabricated zeroes | ✅ |
| Hydration | `0 / 2000 ml`, `+250 ml` / `+500 ml`; after adding, a 500 ml entry appears with time and edit/delete controls | ✅ |
| Hydration guidance | Target disclaimer present ("adjust it with a clinician…") | ✅ |
| Weight & BMI | 85 kg / 179 cm / BMI 26.5, category line + BMI screening disclaimer | ✅ |
| Body-composition caveat | Now shown once, after fixing the duplicate BMI disclaimer (see below) | ✅ (fixed) |
| Goals | "No target" per metric, "No step data recorded today" when no data — unset ≠ default | ✅ |
| Capability registry | Per-metric rows with honest notes: SpO2 "unverified on V15183", body-fat/muscle "no verified sensor", GPS "no route data", HRV "no verified measure", sleep stages "raw codes"; "No capability has been verified on physical hardware yet"; 4 explicitly unsupported | ✅ |
| Live measurements card | Heart rate and ECG entry points visible even when synced history is unsupported; ECG labelled "Not available on this watch." | ✅ |
| Heart rate monitor | Start → band `0x18` toggle ACKed → `0x15/0x0e` sample → UI showed **78 bpm** (`1 samples · 78–78 bpm`); Stop queued the reading | ✅ live |
| Heart-rate persistence | Stop → `/physical/sync` → Mongo `health_readings`: `HEART_RATE=78 bpm`, `DEVICE_MEASURED`, `source=FITPRO`, device `6addcbd88b3ebd0247fbe8d9`, user `6addc6848b3ebd0247fbe8cb` | ✅ live |
| Heart-rate display after sync | `/physical/today` and `/physical/heart-rate` now return the stored 78 bpm even though the device capability list omitted `HEART_RATE`; the app reloads both on next open/refresh | ✅ live API (UI reload pending phone unlock) |
| ECG screen | "ECG is not supported" + disabled Start + explanation; no waveform fabricated | ✅ live |
| Queue recovery | Stale batches from a deleted device are dropped with a notice; no repeated `Wearable device not found` in backend logs after relaunch | ✅ live |
| Weight/goal/trends/insights dialogs | Rendered in widget/audit tests; manually exercised for hydration at minimum | 🟡 partial manual |

### Connectivity checks (2026-10-27)

- From the phone (`192.168.1.2`) the host ports `192.168.1.4:8080` (API) and
  `192.168.1.4:8083` (Keycloak) accept TCP connections; ping RTT ~3 ms.
- Backend container: healthy; `/api/v1/physical/today` answers with a valid
  JWT (`success:true`); `/api/v1/wearable/{id}/capabilities` returns the
  registry. An unauthenticated call correctly returns 401, so a 401 is not a
  connectivity failure.
- AI container: healthy; `POST /api/v1/wellness/physical-insights` returns a
  structured response with `source=AI_SERVICE`.
- The "Unable to reach the server" banner observed during this pass coincided
  with a backend container restart; after `docker compose build backend` +
  `up -d backend` the app loaded the dashboard again without the offline
  banner. The app still shows cached data and an explicit offline line rather
  than pretending to be online.
- Bluetooth: service discovery on this band consistently takes **8–9 s**, only
  ~1 s inside the old 10 s connect timeout. The timeout is now 25 s and a
  timeout closes the half-open GATT; manual sync also force-drops a zombie
  handle. Fresh connects and the full preamble were captured after the change.

### Defect found and fixed during this verification

The Body summary endpoint returns the BMI disclaimer both in `bmi.disclaimer`
and as `limitations[0]`. The screen printed both, so the same sentence appeared
twice and the body-composition limitation was never visible. Fixed by
`BodySummary.additionalLimitations` (filters the already-printed disclaimer)
plus a regression test; the extra limitation is now rendered once.

## Automatic wearable data flow (fixes in this round)

The sync pipeline was reworked so watch data arrives without manual entry:

- **Pairing fetches immediately** (`connectDevice`): after the GATT session is
  established, the first snapshot is read, durably enqueued, uploaded and the
  dashboard refreshed — before the "connected." notice is shown. A failed
  first fetch surfaces an actionable notice but keeps the watch paired.
- **One quiet auto-refresh per app session** (`init` → `_autoSyncFromWatch`):
  a paired cached watch is read automatically on dashboard open, only when
  Bluetooth is on, permissions are granted and the gateway is available.
  Preconditions that need user action skip silently (no warning banner);
  re-entering the screen does not re-trigger BLE activity.
- **"Sync now" funnels through the same pipeline** (`_runDeviceSync`) with a
  bounded 3-attempt reconnect, durable enqueue-first, explicit notices.
- **Screen-scoped periodic refresh** (`syncIfStale`, every 90 s while the
  Physical Wellness screen is resumed): steps are a cumulative device total,
  so a fresh read is what keeps "today" moving. It skips while another sync
  or a live-HR session owns the link, reuses a healthy GATT handle for
  frequent ticks, forces a fresh connection after 10 idle minutes, and never
  raises a banner.
- **Manual sync drops a zombie link first.** Android reports a dead GATT as
  "already connected"; `syncNow()` calls `disconnect()` before reconnecting,
  while the silent path reuses the live session. Native `connect` only
  short-circuits when the platform has actually reported `STATE_CONNECTED`.
- **Service-discovery timeouts are no longer fatal.** Discovery on this band
  measured 8–9 s (inside the old 10 s window by <2 s). The native connect
  timeout is now 25 s and a timeout closes/nulls the half-open GATT instead of
  leaving a handle that makes the next attempt short-circuit without TX.
- **Idempotent native connect** (`WearableChannel.connect`): reconnecting an
  already-connected GATT session no longer opens a second one.
- **Replays rejected once, server-side**: `clientSyncId` is stored on the
  `SyncSession` (unique sparse index); a replay echoes the stored result and
  neither re-saves the device nor grows the audit log.
- **Concurrent/replayed upserts merge instead of 500** (daily-activity
  unique index race) and the optimistic-locked device save retries once.
- **Sleep windows use the wake day at every query site**, so the first night
  of every window is no longer dropped; today's exercise window no longer
  loses 5-min clock-skew sessions.
- **Server rejects are surfaced**: an HTTP-200-but-FAILED/PARTIAL queue batch
  is dropped (unfixable by retry) with exactly the server's reason shown.
- **Today's check-in visible to Mind–Body insights**: range query made
  explicitly inclusive and contract-guarded.

### Test evidence for this round

- Flutter: `physical_wellness_test.dart` now asserts the automatic pipeline —
  pairing uploads the first batch, `init()` auto-fetches a cached paired watch
  once per session (quiet, no banner), skipped silently when Bluetooth is off
  or permissions are missing, reconnect scripts interplay with the pipeline,
  and rejected batches surface the reason. Full suite: **326 passed, 1 skipped**.
- Backend: new/updated tests for sync idempotency (`clientSyncId` replay),
  unique-index race merging, inclusive-range contract (incl. check-ins), wake
  date sleep windows, exercise-day windows, kJ/negative-value validation.
  Full suite: **502 passed, 0 failed**.

## Wearable hardware checklist (FitPro Watch 8, 2026-10-26)

Run with the physical watch (`6D:7D:64:37:03:28`, firmware `V15183`) in range
and the app on the SM-M325F over wireless debugging:

| Check | Action | Expected | Status |
| --- | --- | --- | --- |
| Permission grant | `requestPermissions` from UI | OS dialog → granted, method returns true | ✅ |
| Scan | `scan` (or auto-scan when connecting) | band listed with `deviceIdentifier`/`name`/`rssi` | ✅ (`6D:7D:64:37:03:28`) |
| Connect | `connect` | returns true; UART service discovered; notifications enabled | ✅ (both `setCharacteristicNotification` + CCCD) |
| Time sync | after connect | band clock matches phone (wire `0x12/0x01`) | ✅ (HR frame seconds-of-day matched host clock) |
| Init ACKs | after connect | every preamble frame answered with `0xDC` | ✅ |
| Device info | `0x20/0x02` + GATT `0x180A` | firmware/model/battery read | ✅ (`V15183`, model string, 54 %) |
| Live heart rate | HR screen Start | `0x12/0x18` ACKed, `0x15/0x0e` samples → live bpm | ✅ 78 bpm (and 75 bpm in an earlier session) |
| Live HR persistence | HR screen Stop | queued and uploaded as `DEVICE_MEASURED` | ✅ Mongo record verified |
| ECG | ECG screen | honest unsupported state, no waveform | ✅ (no ECG service/command exists) |
| Snapshot (history) | `readSnapshot` | HEART_RATE, dailyActivity, sleepSessions; no fabricated SpO2/HRV | ✅ steps (423 then +701 delta on 2026-10-26) · 🟡 sleep frames never arrive |
| Sleep stages | snapshot payload | raw codes preserved as `RAW_<n>` with `stageSource=FITPRO_RAW`; no light/deep/REM claim | 🟡 no sleep frames observed |
| SpO2 | snapshot/live HR frame | payload[5] emitted only in the 50–100 % range; 0/out-of-range dropped | ✅ (codec+unit) · 🟡 no real sample observed yet |
| Capability report | after a successful snapshot | metrics reported as unverified; client cannot promote to verified | ✅ (server contract) · 🟡 on-device |
| ACK behavior | stream a full day | gate frames `0x07/0x08/0x10` ACKed; no stalls | 🟡 only init/monitor frames observed |
| Firmware/battery | snapshot payload | `firmwareVersion` ≈ V15183 family; `batteryLevel` 0-100 | ✅ (`V15183`, 54 %) |
| Reconnect resilience | kill/restart app mid-snapshot | no leaked GATT; next snapshot succeeds | ✅ relaunch reconnects (`connect: already connected` short-circuit + fresh session) |
| Degradation | desktop/emulator/no band | dashboard runs with an honest "no wearable" state; no crash | ✅ |
| Phone launch | SM-M325F over wireless debugging | build installs; app launches; Physical Wellness renders | ✅ Oct 2026 |

### Root causes found and fixed during the live pass

1. **Notifications were never registered.** The channel wrote the CCCD
   descriptor but never called `setCharacteristicNotification(rx, true)`.
   Android then delivered nothing to `onCharacteristicChanged` while a host
   `gatttool` session received the same ACKs. Both steps are now performed.
2. **Poisoned sync queue blocked every later upload.** Stale batches that the
   server rejected permanently (404 `Wearable device not found`) stayed at the
   head of the queue forever. Permanent rejections (400/404/409/422) are now
   dropped with a notice; transient failures still retry.
3. **Empty snapshots were enqueued as successful syncs.** A battery-only
   snapshot now produces an honest "connected but no new health data" notice
   and is never uploaded as a reading.
4. **Stop → Start threw "Stream has already been listened to".** The Dart
   gateway cached the single-subscription `async*` live stream; it is now
   created per call.
5. **Stopping the sensor depended on stream teardown.** `await
   subscription.cancel()` could stall; both screens now detach the
   subscription with `unawaited(...)` and always send the hardware stop.
6. **Leaving the screen left the optical sensor running.** HR/ECG screens now
   stop a running session in `dispose`.
7. **"Watch Watch 8".** The scan name was parsed into a manufacturer, so the
   label repeated the first word. The manufacturer is no longer invented and
   `displayName` de-duplicates a prefix.
8. **A stored heart-rate reading was hidden by a stale capability list.**
   The history snapshot returned no HR frames, so `HEART_RATE` was absent
   from `wearable_devices.capabilities`; `/physical/today` and
   `/physical/heart-rate` returned "unsupported" even though live readings
   were saved. Both endpoints now let observed rows win over the declaration,
   and the live-measurement path reports `HEART_RATE / SUPPORTED_UNVERIFIED`
   so the registry catches up without self-certifying verification.
   Verified against the running backend with a throwaway account whose device
   declared only `STEPS`: `/today` returned `supported=true, latest=78` and
   `/heart-rate` returned `supported=true, available=true, latest=78`.
9. **The stored day total was replaced by the newest delta.** FitPro deletes
   each history chunk after sending it, so a later fetch only carries new
   intervals. The 423-step row for 2026-10-26 was overwritten by a 701-step
   delta. Daily rows are now marked `INTERVAL_DELTA` and added server-side;
   `PhysicalSyncService` adds them only for that explicit value, so cumulative
   device totals still replace. Retries stay idempotent because the queue
   reuses its `clientSyncId` and the server echoes the stored result.
10. **Calories were stored 1000x too large.** The band's low-19-bit field is
    thousandths of a kcal (captured 2600 -> 2.6 kcal), so a 701-step day stored
    14,000 kcal. `FitProProtocol` now converts at decode time, and both stale
    rows were corrected in Mongo.
11. **The `0x0c` "day summary" frame is not usable.** Two captures from the
    same afternoon decoded to 1 step / 3.3e9 m and 115,996 steps / 81,247 m.
    It is ACKed (so the band keeps streaming) but never persisted; step chunks
    are the only activity source. The bogus 115,996-step row it created was
    corrected.
12. **Distance under 1 km read as "0.04 km" and was ellipsised.** The stat
    tile now shows metres below 1 km (`42 m`) and two-decimal kilometres above
    (`4.84 km`).
13. **A failed restart wiped the session the user was still looking at.** The
    monitor screen cleared its readings before asking the band to start, so a
    refused restart (out of range, busy link) erased the confirmed session.
    Readings are now cleared only after a confirmed start; the error is shown
    alongside the previous values (`heart_rate_monitor_screen_test.dart`).
14. **Saved confirmations were silently dropped on the Physical screen.** A
    successful save inserts a notice banner at the top of the list, which
    rebuilds the cards positionally and can unmount the card holding the
    callback's `BuildContext`. The old `_showLifestyleResult` guard then
    returned without showing anything. All six mutation sites now capture the
    `ScaffoldMessenger` before awaiting, and the helper checks
    `messenger.mounted`. Verified on-device: saving 85 kg / 180 cm showed
    "Measurement saved." (the duplicate verification row was removed
    afterwards, leaving the six real measurements untouched).

15. **A positive PHQ-9 item 9 produced no escalation.** The only safety copy
    was a static client note beside the question. The backend now derives
    `Screening.hasSelfHarmSignal()` (item 9 > 0), stores it as
    `wellness_profiles.safetyFlag`, back-fills legacy profiles on read, exposes
    it on the dashboard, and the app shows a non-diagnostic support card on the
    dashboard and post-screening profile. Live: the main account's stored
    item 9 is 3, the profile and dashboard report `safetyFlag=true`, and the
    banner was captured on the physical phone.
16. **A terminal AI failure left the profile pending forever.** `fail()` and
    the stale-job sweeper now publish the deterministic analysis via
    `WellnessProfileService.completeFor()`, so the user keeps a usable score
    and narrative while a retry can still replace the wording. Live proof: a
    throwaway job was claimed then failed with a simulated provider outage;
    Mongo shows `FAILED` for the job and `COMPLETED` for the profile with a
    322-character deterministic insight.
17. **Real mood check-ins never reached Mind–Body patterns.** The app writes
    `/moods`, while the pattern engine read only `daily_checkins` (always 0).
    Mood entries are now merged by local day, with stored check-ins winning.
    Live: `/physical/insights` moved from `moodCheckins: 0` to `1`.
18. **AI-service routes were callable without authentication.** When
    `AI_INBOUND_AUTH_REQUIRED=true`, every `/api/v1` request now needs the
    shared `X-Internal-Api-Key`; `/health` stays public for probes. The coach
    RAG client now sends the header too. Live: no key → 401, shared key → 200,
    health → 200, and a backend journal analysis still completed (HTTP 200).
19. **Mood timestamps could be arbitrarily in the future.** `recordedAt` more
    than five minutes ahead of server time is rejected. Live: a `+2 h` POST
    returned 400 `VALIDATION_FAILED` and wrote no row.
20. **The dashboard called a static insight "Today's".** The label is now
    "Your latest AI insight"; verified on-device.
21. **Physical "AI wording" implied generative AI.** The engine is a
    deterministic rule table; the UI now labels service-added text
    "Personalised" and says when wording was unavailable, without claiming an
    LLM. Optional LLM wording is now implemented behind strict validation and is
    only labelled as such when `generated_by=llm`.
22. **There was no combined mental–physical insight.** A new AI endpoint
    (`/wellness/combined-insight`), a backend endpoint of the same name, a
    deterministic Java composer, a pending-profile guard, a Java-owned safety
    append and a Redis cache were added. Only anonymised aggregates are sent.
23. **LLM wording could not be distinguished from rule text.** The AI service
    now returns `generated_by` (`llm` or `rules`) for both physical and
    combined wording; the app renders "Personalised"/"Rule-based" and
    "AI-personalised"/"Based on your data" respectively.
24. **Journal text was stored in plaintext.** Titles, bodies, AI summaries,
    themes and reflection prompts are sealed with AES-256-GCM
    (`enc:v1:<iv>:<ciphertext>`), decrypted only on read, and legacy rows are
    encrypted by an idempotent startup migration. Production refuses to boot
    with an unset/short/sample key.
25. **Assessment history existed only as an API.** `AssessmentHistoryScreen`
    and `/assessment-history` were added with Check-in and Profile entry
    points, showing stored status, dates and answered sections without
    recomputing scores client-side.
26. **Redis was provisioned but unused.** The combined insight is cached by a
    SHA-256 fingerprint of the profile + physical aggregates for 30 minutes
    (best-effort: a cache failure never breaks the endpoint).
27. **Several services had no internal health probe.** Compose now defines
    in-container healthchecks for all eight services; `docker inspect` reports
    `healthy` for each and the probes were executed manually.
28. **A days-old stored mood was described as "today" by the combined LLM.**
    The untimestamped mood fields are no longer sent to the AI service, the
    prompt forbids recency claims, and a request-contract test pins their
    absence. The live re-run contains no such claim.

## Mental–physical integration and data-at-rest (2026-10-27)

Live checks against the rebuilt containers (throwaway account
`6addd9c3d7d81b2b3f4a0cb7` for writes, main account for the safety case):

| Check | Observation | Status |
| --- | --- | --- |
| Combined endpoint | `GET /api/v1/wellness/combined-insight` → 200; `available=true`; 669-char narrative; coverage exactly as stored | ✅ live |
| LLM combined wording | Main account `generatedBy=llm`; strict validation, no invented digits, no diagnosis claim | ✅ live |
| Deterministic combined fallback | Java composer returns grounded text (`generatedBy=rules`) when the AI service is unavailable (unit test); the AI service also returns `generated_by=rules` when model output fails validation (observed live) | ✅ unit + live AI-rules |
| Safety escalation on combined path | Main account `safetyFlag=true`; Java appends the self-harm support paragraph and a "Reach out today" suggestion; model cannot suppress it | ✅ live |
| Combined honesty fix | No "feeling happy today" or equivalent recency claim in the re-run | ✅ live |
| Redis cache | 2 keys `combined-insight:v1:*`, TTL 1789/1795 s, second read `cached=true` with identical text | ✅ live |
| AI direct combined | 401 without `X-Internal-Api-Key`, 200 with it; `/health` remains 200 | ✅ live |
| Physical LLM wording | Direct call `generated_by=llm`, grounded suggestions, no digits; rule fallback otherwise | ✅ live |
| Journal at rest | 3/3 throwaway rows have `enc:v1:` title/body/summary; 0 plaintext; the legacy row was migrated at startup | ✅ live |
| Journal read path | API returns plaintext title/body/summary for the owner; search for a body word returns the row | ✅ live |
| Assessment history | `GET /screenings/me` returns 2 stored assessments with status/timestamps; screen/route/widget tests pass | ✅ live + unit |
| Main-account safety of writes | Main account counts unchanged (0 journals, 1 screening, 1 profile); all writes stayed on the throwaway account | ✅ live |
| Internal health probes | All 8 containers `healthy`; in-container probes return 200/PONG/ping | ✅ live |

## Protocol validation procedure

1. Start with `docs/wearables/fitpro-protocol.md` byte layouts.
2. Capture raw notifications on-device (log + `adb` + optional BLE sniffer);
   diff against the documented frames.
3. Any constant fix applies in **`FitProProtocol.kt` only**, with matching
   `FitProProtocolTest.kt` vector updates, then re-run
   `./gradlew :app:testDebugUnitTest`.
4. Only after that run may a capability be marked verified, and only by the
   server — the client report path downgrades `SUPPORTED_VERIFIED` to
   `SUPPORTED_UNVERIFIED` by design.

## Gates

- Flutter: `cd app && flutter test` → **364 passed, 1 skipped, 0 failed**.
- Backend: `cd backend && mvn test` → **572 passed, 0 failed, 0 errors,
  0 skipped**.
- Android app unit: `cd app/android && ./gradlew :app:testDebugUnitTest` →
  **41 passed** (23 protocol + 18 assembler).
- AI service: `cd ai-service && pytest` → **164 passed**, 1 Qdrant
  client-compatibility warning.
- Live feature/API verification:
  `python3 /tmp/opencode/verify_final_features.py` → **24/24 checks**
  (combined insight, cache hit, assessment history, journal ciphertext vs API
  plaintext, AI inbound auth, physical LLM wording).
- Live API: `python3 /tmp/opencode/e2e_lifestyle.py` → **74/74 checks** against
  the rebuilt containers.
- Live HR visibility: `python3 /tmp/opencode/verify_hr_visibility.py` → PASS
  (device declaring only `STEPS`, stored 78 bpm still returned by `/today`
  and `/heart-rate`).
- Live app → band → backend: **verified 2026-10-26** (see the hardware
  checklist above and `fitpro-protocol.md` for captured frames).

## Verification limitation (hardware)

Transport, initialization, device info, ACK flow, live heart rate, and step
history (423 steps / 346 m / 8 kcal for 2026-10-26, later +701 steps / +484 m
/ +14 kcal delta) are verified on a physical
FitPro Watch 8. Sleep history is not: the band acknowledged both the step
request and the separate `0x15`/`0x0d`/`0x01` sleep request (MFitX
`requestSleepHistory`, sent 2026-10-27) but emitted no `0x15`/`0x03` sleep
frames. A fresh fetch on 2026-10-27 did return 19 interval chunks
(+701 steps / +484 m for 2026-10-26), confirming live step increments after
movement. The calorie field was initially stored as raw thousandths of a kcal
(14,000 kcal/day); the codec now divides by 1000, and the captured
2600 → 2.6 kcal chunk is pinned by a unit test. The `0x0c` day-summary frame is
ignored: its layout varied between connections (one capture decoded to
115,996 steps / 81,247 m). Because the band deletes history after sending it
once, daily rows are uploaded as `INTERVAL_DELTA` and added server-side. No
sleep or HRV reading is claimed as device-measured. SpO2 is decoded from the documented
heart-rate-frame byte and range-filtered, but no real SpO2 sample has been
observed yet, so its capability remains `UNKNOWN` until a record arrives.

`./gradlew testDebugUnitTest` for the whole tree still fails in Flutter's own
`:integration_test` plugin (`Mockito cannot mock FlutterView` under JDK 25).
That is upstream and unrelated; `:app:testDebugUnitTest` is green.

## Verification status (non-hardware, updated 2026-10-28)

- **Journal media is sealed at rest.** Titles, bodies, AI summaries, themes and
  prompts are sealed with AES-256-GCM, and uploaded images, audio and video are
  now sealed too, in 1 MiB authenticated chunks (`MBE2` frame) with the original
  content type kept as object metadata. Sealed media is served back through
  `GET /api/v1/media/object` carrying a short-lived per-object signature instead
  of a storage presigned URL, because the bytes have to pass through the backend
  to be opened. Live check: a 95-byte PNG upload is stored as 123 bytes of
  ciphertext (no `\x89PNG` header) and the journal `imageUrl` returns the exact
  original bytes; a tampered signature and an expired token both return 403.
  Objects written before the change are recognised by the missing marker and
  still served, so switching encryption on never strands earlier media.
- **Journal search covers the whole archive.** Because the body is encrypted,
  Mongo cannot regex it, so search still decrypts and filters after the fact —
  but it now pages through the caller's own entries in 500-row chunks instead of
  reading only the newest 1,000, with a 20,000-row per-request ceiling that logs
  a warning and reports `hasMore` when it is reached. Ownership remains enforced
  by the scoped query.
- **Combined insight cache may be up to 30 minutes old.** The key includes a
  SHA-256 fingerprint of the profile and physical aggregates. It now also
  covers `profile.updatedAt()`, heart-rate days, missing sources and the actual
  insight/recommendation wording, so a changed rule or profile revision misses
  the cache inside the TTL. The TTL remains the backstop and is accepted.
- **On-device capture.** The combined mind–body card, the rebuilt dashboard, the
  live heart-rate screen and the Physical Wellness hub are now captured on the
  physical phone and retained locally in `docs/screenshots/`, but they are not
  published because they show personal health data. The assessment-history
  screen still has no capture — wireless debugging dropped again mid-session
  (all ports refused, no mDNS) — and remains covered by widget/route tests only.
- **Combined safety text never drops the request to reach out.** The escalation
  is split into reason, outreach and crisis. If the model names self-harm but
  omits outreach, both Java and the AI service add the cause-free outreach
  sentence plus the crisis line, so the cause is not repeated and the actionable
  request is never lost. Pinned by backend and AI regression tests, including
  "the model only names the cause".
- **Physical LLM wording is verified via the AI endpoint.** With the main
  account's sparse data the backend returns `aiEnhanced=false`; the seeded
  fixture produced `aiEnhanced=true` earlier and the direct endpoint returns
  `generated_by=llm`. No data was fabricated to force the backend path.
- **Phone reached the backend without a special build.** A physical device no
  longer depends on `--dart-define=API_BASE_URL`: the app resolves its base URL
  at runtime, a saved address overrides the `10.0.2.2` default, Settings →
  Server connection shows the address, tests it and lets it be changed. The
  login screen links to the same screen, so an unreachable default can be fixed
  before sign-in, and journal media upload/delete now use the same runtime
  address instead of the compiled default.
- **Unknown routes are 404, not 500.** `GlobalExceptionHandler` maps Spring's
  `NoResourceFoundException` (including trailing-slash URLs) to `404 NOT_FOUND`,
  so a mistyped address no longer looks like a backend outage.
- **The FER weights are not in Git.** `vit_fer_fp16.tflite` is 171.9 MB twice,
  the public repository has a 100 MB file limit, and the upstream license was
  never recorded. Both copies are ignored; provision them locally and verify
  against `app/assets/models/vit_fer_manifest.json`.

### Bluetooth connect, measured on the real band (2026-10-28)

| Check | Observation | Status |
| --- | --- | --- |
| Connect | `onConnectionStateChange CONNECTED`, status 0 | ✅ live |
| Service discovery | 8.2 s, inside the 25 s connect timeout | ✅ live |
| Preamble + ACKs | `0x12`/`0x0a`, clock sync, `0x12`/`0x01`, `0x1a`/`0x0a`, `0x1a`/`0x0c`, `0x12`/`0x15`, `0x12`/`0xff`, `0x1a`/`0x01`, `0x1a`/`0x0f`, `0x1a`/`0x10`, all ACKed | ✅ live |
| Device info | `0x20`/`0x02` → `V15183`, battery 54 % | ✅ live |
| Step history | `0x15`/`0x06` sent and ACKed; band replayed no new chunks (no movement since the last sync) | ✅ live · honest empty result |
| Live heart rate | Start → `0x12`/`0x18` ACKed → `0x15`/`0x0e` sample → **74 bpm** in the app, `1 samples · 74–74 bpm` | ✅ live |
| Sleep history | `0x15`/`0x03` still never emitted after the request is ACKed | 🟡 BLOCKED (firmware) |

## Known risks

- Protocol is reverse-engineered; offsets could drift across firmware lines.
  The codec is isolated so drift fixes stay in one file.
- `readSnapshot` uses an 8 s collection window plus up to three 4 s
  extensions (30 s watchdog); a band that replays more than ~3 days of
  history may still need pagination (future work).
- Sleep stage labels are raw codes; mapping them to light/deep/REM requires a
  validation run and is intentionally not claimed. No sleep frame has been
  observed from this unit yet.
- SpO2 is emitted only from the heart-rate frame's documented byte and only
  in the 50–100 % range; it stays `UNKNOWN` until a real record is stored.
  HRV is `UNSUPPORTED` because the frame layout has no HRV field.
- Body-fat / muscle mass / GPS route are explicitly unsupported for FitPro and
  cannot be promoted by a client report.
- BMI is a limited screening measure, labelled as such; it is not a diagnosis.
- Goal targets are nullable; suggested defaults are labelled separately and
  never presented as the user's own target.
- Weight is excluded from Mind–Body pattern inference on purpose.
- iOS is out of scope for the native bridge (Android only); the Dart gateway
  degrades to an honest "no wearable" state.
- Offline writes are never reported as saved: retryable failures queue a
  mutation, permanent 4xx rejections surface immediately.
