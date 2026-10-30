# Synora (MindEase) — final audit and remediation report

**Date:** 2026-10-27  
**Scope:** Flutter app, Spring Boot backend, Python AI service, MongoDB, RabbitMQ,
Redis, Qdrant, Keycloak, S3Mock, and the physical FitPro Watch 8.  
**Rule applied:** a capability is only reported as verified when a real stored
record or a live on-device/API observation exists. No hardware reading, AI
narrative, or waveform is fabricated.

---

## A. Overall status

**PASS for every in-scope requirement that could be verified on this
environment; BLOCKED only for sleep, which the band firmware never emits.**

- All eight runnable containers report `healthy`, and every service now carries
  an internal health probe (backend, AI, Mongo, Redis, RabbitMQ, Qdrant,
  Keycloak, S3Mock).
- The physical watch path (BLE lifecycle, steps, distance, calories, live heart
  rate, sync queue, capability honesty) is verified on the real phone and band.
- The mental screening → deterministic scoring → AI job → wellness profile
  pipeline is verified against live infrastructure.
- The previously listed gaps are now implemented and verified live:
  **combined mental–physical insight**, **LLM-backed physical wording**,
  **journal encryption at rest**, **assessment-history UI**, **Redis caching**,
  and **internal health probes**.
- The combined narrative is produced by the AI service when its output passes
  strict grounding validation, otherwise by a deterministic composer; the
  client labels the source honestly (`AI-personalised` vs `Based on your data`).
- The PHQ-9 item-9 escalation is appended in Java on the combined path; no model
  can suppress it.
- Sleep remains **BLOCKED** by the band firmware (no `0x15/0x03` frames).
- New UI (combined card, assessment history) is covered by widget/route tests,
  but could not be screenshotted on the phone: wireless debugging stopped
  accepting connections before that pass (see E2).

### Test gates (final)

| Gate | Result |
|---|---|
| Backend `mvn test` | **572 passed, 0 failed, 0 errors, 0 skipped** |
| Flutter `flutter test` | **364 passed, 1 skipped, 0 failed** |
| Android `:app:testDebugUnitTest` | **41 passed, 0 failed** |
| AI service `pytest` | **164 passed** |
| Live feature/API verification | **24/24 checks passed** (combined, cache, history, journal, auth, physical wording) |

The one skipped Flutter test is an intentional platform-skipped test; the
upstream `:integration_test` module still cannot run under this JDK (Mockito
cannot mock `FlutterView`), which is unrelated to the app module.

---

## B. Service health (final)

| Service | Probe (internal to the container) | Result |
|---|---|---|
| Backend | `curl -fs http://localhost:8080/actuator/health` | **200 UP**; mongo, rabbit, redis, diskSpace, ping, readiness all UP |
| AI service | Python `urllib` → `http://localhost:8000/health` | **200**; `emotion_model=loaded`, `text_analyzer=transformer` |
| Qdrant | `GET /readyz` on `:6333` | **200 OK** (`mindease_chunks`, 384-d cosine) |
| RabbitMQ | `rabbitmq-diagnostics -q ping` | **Ping succeeded**; `ai_tasks` queue reachable |
| Redis | `redis-cli -a $REDIS_PASSWORD ping` | **PONG**; `DBSIZE=2` (combined-insight cache entries) |
| S3Mock | `wget --spider http://localhost:9090/favicon.ico` | **200** |
| Keycloak | HTTP `GET /realms/mindease` on `:8080` | **200 OK**; OIDC discovery 200 |
| MongoDB | `mongosh` authenticated `ping` | **1**; all queried collections readable |
| AI inbound auth | `/api/v1/risk/assess` and `/wellness/*` | **401 without key, 200 with shared key**; `/health` still 200 |

> The probes are defined in `docker/compose.base.yml`, so they run inside each
> container rather than depending on a host-side `curl`. All eight containers
> therefore report `healthy` on `docker inspect`.

---

## C. Wellness data inventory (main account `6addc6848b3ebd0247fbe8cb`)

| Collection | Rows | Notes |
|---|---:|---|
| `daily_activity` | 2 | 2026-10-26: 701 steps / 484 m / 14 kcal; 2026-10-27: 61 steps / 42 m / 1.2 kcal |
| `health_readings` | 8 | Live HR history; latest **82 bpm** at 15:46:12Z, today average 79.8 |
| `sleep_sessions` | 0 | Band never emitted sleep frames (BLOCKED) |
| `hydration_entries` | 4 | Today **250 ml** (1 entry); prior day 1,750 ml (3 entries); target 2,000 ml |
| `body_measurements` | 6 | Six real measurements; duplicate verification row removed earlier |
| `wellness_goals` | 1 | User-owned target |
| `mood_entries` | 1 | `happy`, 2026-10-25 |
| `screenings` | 1 | PHQ-9 item 9 = 3 → positive safety screen |
| `wellness_profiles` | 1 | COMPLETED, score **54**, stress LOW, lifestyle 64, sleep FAIR, focus MOOD_SUPPORT, insight 747 chars, `safetyFlag=true` |
| `ai_analysis_jobs` | 1 | COMPLETED, attempt 1, insight stored |
| `journal_entries` | 0 | No real main-account journal |
| `daily_checkins` | 0 | App uses `/moods`; mood entries are merged into pattern context |

The main account was re-checked after every verification pass: profile score,
stress, lifestyle, sleep, focus, insight, the screening answers, readings,
hydration, measurements and goals are unchanged. The only earlier main-account
change was the derived `safetyFlag` back-fill from the stored PHQ-9 answer.

**Throwaway verification account** `6addd9c3d7d81b2b3f4a0cb7`
(`e2e.lifestyle@example.com`) was used for all write tests: 2 screenings,
2 profiles, 2 AI jobs (one deliberately failed), **3 journal entries**, 4 mood
entries, 14 activity rows, 14 fixture sleep sessions, 1 hydration row.
Its sleep/activity rows are seeded audit fixtures and are **not** hardware
evidence. No main-account wellness rows were overwritten or deleted.

---

## D. AI analysis verification

### D1. Mental pipeline (live, main account)

- Screening submitted and stored: PHQ-9 `[1,2,2,2,2,1,1,0,3]`, GAD-7 `[2×7]`,
  PSS-10 raw `0×10`, WHO-5 `[5×5]`.
- Deterministic profile: score **54**, stress **LOW**, lifestyle **64**, sleep
  **FAIR**, focus **MOOD_SUPPORT**.
- AI job: **COMPLETED on attempt 1**, insight persisted (747 chars).
- Dashboard: `aiReady=true`, `aiStatus=COMPLETED`, score 54.
- Restart persistence was verified: profile, score, insight and `aiReady` were
  unchanged after a backend restart.

### D2. Terminal-failure fallback (live, throwaway account)

- The AI service was stopped, a new assessment submitted, the job claimed
  through the internal endpoint, then failed with
  `{"error":"simulated provider outage"}`.
- Mongo result: job **FAILED**; linked profile **COMPLETED** with a
  322-character deterministic insight and score 64.
- A Gemini/Rabbit outage therefore no longer strands the user on an indefinite
  “AI pending” screen. A later retry can still replace the wording.

### D3. Safety escalation (live)

- The main account’s stored PHQ-9 item 9 is **3** (positive).
- The profile returns `safetyFlag=true`, the dashboard returns
  `safetyFlag=true`, and the support card was captured on the physical phone.
- Legacy profiles with no stored flag are back-filled from their linked
  assessment on read.
- On the combined endpoint the safety paragraph is appended **in Java** when
  the model did not include it: live main-account response contains
  “Because one of your answers mentioned thoughts of self-harm…”, plus a
  “Reach out today” suggestion. The model never controls this text.

### D4. Physical / Mind–Body analysis (live)

- `/physical/insights` reports `moodCheckins: 1` for the main account (real
  `/moods` entries reach the pattern engine; previously 0).
- Current real-data response: `sufficientData=false`, `aiEnhanced=false`; one
  `no_pattern_detected` INFO insight with coverage 2 activity days / 0 sleep /
  2 hydration / 1 mood. This is correct sparse-data behavior.
- The seeded throwaway fixture previously produced `sufficientData=true`,
  `aiEnhanced=true`, two patterns (`sleep_below_baseline`,
  `activity_below_baseline`) and four recommendations.
- **Generative wording is now real but optional:** the AI service exposes
  `/wellness/physical-insights`, whose LLM output is accepted only when it
  invents no digits and contains no diagnosis/medication/restriction language.
  Live direct call returned `generated_by=llm` with grounded suggestions.
  When the call fails, the rule engine’s recommendations are returned unchanged.
- The UI labels service wording **“Personalised”**, rule-engine wording
  **“Rule-based”**, and states when wording was unavailable.

### D5. AI-service inbound authentication (live)

- `AI_INBOUND_AUTH_REQUIRED=true` in the running container.
- `POST /api/v1/risk/assess` and `/api/v1/wellness/*` without
  `X-Internal-Api-Key` → **401**.
- Same requests with the shared key → **200**.
- `GET /health` → **200** without a key.
- Backend → AI journal analysis still succeeds (HTTP 200, `COMPLETED`).

### D6. Combined mental–physical insight (live)

- New backend endpoint `GET /api/v1/wellness/combined-insight` and AI endpoint
  `POST /api/v1/wellness/combined-insight`.
- Only anonymised aggregates are transmitted: mental scores/focus/safety flag
  and physical coverage/pattern ids. No answers, journal text, readings, device
  ids or free text.
- **Main account (live):** `available=true`, `generatedBy=llm`,
  `safetyFlag=true`, narrative 603 chars, deterministic safety paragraph
  present, `note` says “no measurement was invented… not a diagnosis”.
- **Throwaway account (live):** `available=true`, deterministic **and** LLM
  variants observed across runs, coverage returned exactly as stored
  (`windowDays=14`, activity 14 / sleep 14 / hydration 1 / mood 3 — fixture
  data), suggestions grounded, no invented numbers.
- **Honesty:** a day-old mood label was being turned into “feeling happy
  today” by the LLM. The untimestamped mood fields are no longer sent, a prompt
  rule forbids recency claims, and a request-contract test pins their absence.
  The re-run live narrative contains no such claim.
- **Deterministic fallback:** when the AI service is unavailable, a Java
  composer produces a narrative from the same aggregates (unit-tested); when
  the AI service rejects the model output it returns its own deterministic
  text with `generated_by=rules` (observed live). Either way the endpoint keeps
  returning 200.
- **Pending guard:** a profile whose status is not `COMPLETED` returns
  `available=false` with an explanatory note instead of composing from null
  scores (unit-tested).
- **Cache:** second live read returned `cached=true` with an identical
  narrative. Redis holds one key per user+fingerprint under
  `combined-insight:v1:<user>:<sha256>` with a ~30-minute TTL (observed 1789 s
  and 1795 s).
- **Client:** the dashboard card renders the source label from
  `generatedBy` (`AI-personalised` only for `llm`, otherwise
  `Based on your data`), the server coverage line, suggestions and the
  non-diagnostic note. Widget tests cover both labels and the hidden state.

---

## E. Defect and remediation report

### E1. Fixed during this audit

| # | Severity | Defect / root cause | Evidence | Change | Regression |
|---|---|---|---|---|---|
| 1 | High (UX trust) | Saved confirmations silently disappeared. Inserting the notice banner rebuilt the list positionally and unmounted the card `BuildContext`; `if (context.mounted)` then skipped the SnackBar. | Hydration/body saves persisted but no message appeared on device | All 6 mutation sites capture `ScaffoldMessenger` before awaits; helper checks `messenger.mounted` | Flutter suite; on-device “Measurement saved.” captured |
| 2 | High (data loss) | Failed HR restart cleared readings already shown | Restart while band refused erased session | Clear samples only after confirmed start; error shown alongside previous values | `heart_rate_monitor_screen_test.dart` 7/7 |
| 3 | High (data integrity) | New step delta replaced the stored day total | 423-step row overwritten by 701-step delta | `INTERVAL_DELTA` added server-side; retries idempotent via `clientSyncId` | Backend tests + live multi-day rows |
| 4 | High (units) | Calories stored 1,000× too large | 701-step day stored 14,000 kcal | Codec divides raw field by 1000 | Unit test pins 2600 → 2.6 kcal; stored row is 14 kcal |
| 5 | High (bad data) | `0x0c` “day summary” decoded to garbage (115,996 steps / 81,247 m) | Two captures differed wildly | ACK only; never persisted | Tests + corrected rows |
| 6 | High (stuck sync) | Poisoned queue blocked all later uploads | Stale 404 batch at head forever | Permanent 4xx dropped with notice; transient retries retained | Queue tests |
| 7 | Medium | Battery-only snapshot uploaded as a successful sync | Empty snapshot showed “synced” | Honest “connected, no new health data”; never enqueued | Queue tests |
| 8 | Medium | Stored HR hidden by stale capability list | `/today` returned unsupported despite saved readings | Observed rows win over declared capabilities; live path reports `SUPPORTED_UNVERIFIED` | Live `/today` + `/heart-rate` |
| 9 | Low | Distance under 1 km rendered 0.04 km and ellipsised | UI screenshot | `distanceLabel()`: metres below 1 km, 2-dec km above | Widget tests; on-device “42 m” |
| 10 | Low | “Watch Watch 8” | Scan label duplication | Manufacturer not invented; `displayName` de-duplicates | On-device |
| 11 | High (availability) | No deterministic mental fallback when the AI job permanently failed; `completeFor()` had no production caller | `grep completeFor(` showed only the definition; `fail()` never finalised the profile | `fail()` and `AiStaleJobSweeper` now call `expire()`/fallback; profile is completed with deterministic scores + narrative | Live simulated outage: job FAILED, profile COMPLETED/322-char insight; backend tests |
| 12 | High (safety) | PHQ-9 item 9 had only a static client note; no backend escalation | `_CrisisNote` always shown; no item flag in screening service | `Screening.hasSelfHarmSignal()`, `wellness_profiles.safetyFlag`, legacy back-fill, dashboard + profile support card | Live `safetyFlag=true`; on-device banner; backend + Flutter tests |
| 13 | Medium | Mood check-ins did not contribute to AI/physical insight; `daily_checkins` is never created by the app | `daily_checkins=0`; app uses `/moods`; mental AI used onboarding mood only | `PhysicalInsightService` merges mood entries by local day; stored check-ins win | Live `/physical/insights` `moodCheckins: 1`; service tests |
| 14 | Medium | AI-service routes were unauthenticated | Direct POST to `127.0.0.1:8000/api/v1/...` returned 200 without a key | `AI_INBOUND_AUTH_REQUIRED` middleware + `X-Internal-Api-Key`; coach RAG client sends it; health stays public | Live 401/200; backend journal analysis 200; AI tests |
| 15 | Low | Mood `recordedAt` accepted future timestamps | Fixture 2 h ahead stored and used as “current” | Reject more than 5 min ahead (`VALIDATION_FAILED`) | Live +2 h POST → 400, no write; MoodService tests |
| 16 | Low | `todayInsight` was static once generated; label implied live | Insight said “today” while later mood was low | Dashboard label changed to “Your latest AI insight” | On-device screenshot; Flutter tests |
| 17 | Medium | Physical “AI wording” implied generative AI although it was a deterministic rule table | `physical_insights.py` returned fixed rule text | Rule engine remains the safe default; optional LLM wording added behind strict validation; UI says “Personalised”/“Rule-based” | Live `generated_by=llm` direct call; Flutter suite |
| 18 | High (scope) | Combined mental–physical AI did not exist | No shared context/prompt/endpoint | New AI + backend endpoints, deterministic composer, strict validation, Java safety append, pending guard, Redis cache, dashboard card | 24/24 live checks; 547 backend + 345 Flutter tests |
| 19 | High (privacy) | Journal title/body/summary stored as plaintext in MongoDB | DB rows readable as plaintext; no encryption code | AES-256-GCM field cipher (`enc:v1:`), startup migration of legacy rows, decrypt-on-read, encrypted AI output, production key guard | 3/3 throwaway rows ciphertext incl. migrated legacy; API plaintext; search works; cipher/migration/service tests |
| 20 | Medium | Assessment history stored but not surfaced in the app | `/screenings/me` existed; UI only showed the latest profile | `AssessmentHistoryScreen`, `/assessment-history` route, Check-in + Profile entry points, status/date/section labels | Widget/model/route tests; live API returns 2 rows for the throwaway account |
| 21 | Low | Redis provisioned but unused | `dbsize=0`; no cache layer | `CombinedInsightCache` with data fingerprint + 30-min TTL; best-effort (cache outage ignored) | Live: 2 keys, TTL 1789/1795 s, second read `cached=true` |
| 22 | Low (verification) | Several containers had no health probe and internal endpoints were unverifiable | Only public OIDC/console checks | Internal healthchecks for all 8 services in compose | All 8 `healthy`; probes executed inside containers |
| 23 | Medium (honesty) | Combined LLM turned a days-old stored mood into “feeling happy today” | Live narrative on 2026-10-27 | Stop sending untimestamped mood fields; prompt rule forbids recency claims; request-contract test | Re-run: no recency claim; test pins absence; 547 backend tests |

### E2. Remaining defects / gaps (not hidden)

| # | Severity | Issue | Evidence | Impact / remaining work |
|---|---|---|---|---|
| 24 | BLOCKED | Sleep frames never arrive | `0x15/0x03` unseen across logged sessions; 0 `sleep_sessions` on the real account; the sleep request is ACKed but silent | Hardware/firmware limitation; sleep/stages remain unverified |
| 25 | Medium | Journal **media** (image/audio/video) is not covered by the field cipher | Only title/content/summary/themes/prompt are sealed; media lives in S3Mock by key | Encrypt or use SSE-KMS for media before production; text is protected |
| 26 | Low | Journal search is bounded to the newest 1,000 entries and decrypts client-side of Mongo | `SEARCH_SCAN_LIMIT=1000` in `JournalService` | Deterministic and user-scoped; very large archives need a searchable index (e.g. blind index) |
| 27 | Low | Combined cache may serve a result up to 30 min old until the fingerprint changes or TTL expires | TTL 1789–1795 s observed | Accepted trade-off; TTL configurable via `COMBINED_INSIGHT_CACHE_TTL` |
| 28 | Low (verification) | New combined card and assessment-history screen were not captured on the phone | Phone `192.168.1.2:39245` refuses adb; no mDNS; ports closed | Widget/route tests pass; capture on device when wireless debugging is restored |
| 29 | Medium | Combined safety text can repeat itself when the model already mentions reaching out | Live main-account narrative contains the model sentence and the appended Java paragraph | Deliberate: the escalation must not depend on the model; deduplicating risks dropping the crisis sentence |
| 30 | Low | Keycloak password grant returns `unauthorized_client` | Direct grant not enabled on the realm | Not a failure: OIDC/app login is verified; direct grant is unnecessary and should stay disabled |
| 31 | BLOCKED | Physical LLM wording is verified via the AI endpoint, not from the backend’s live sparse dataset | Main account `aiEnhanced=false` because coverage is insufficient; seeded fixture produced `aiEnhanced=true` earlier | Correct behavior; no fabrication was introduced to force it |

---

## F. Acceptance checklist

| Requirement | Status | Evidence |
|---|---|---|
| Services start and report healthy | **PASS** | 8/8 `healthy`; internal probes 200/PONG/ping |
| Physical steps/distance/calories sync from the real band | **PASS** | Live `/physical/today`: 61 steps, 42 m, 1.2 kcal; Mongo rows |
| Live heart rate measured, stored, and displayed | **PASS** | 82 bpm in Mongo and `/today`; backend sync `received=1 accepted=1` |
| Sleep and sleep stages | **BLOCKED** | No `0x15/0x03` frames; 0 sleep sessions |
| Mental screening produces deterministic scores | **PASS** | Score 54, sub-scores stored; profile completed |
| AI job completes and persists a validated insight | **PASS** | Job COMPLETED attempt 1; 747-char insight |
| Terminal AI failure still yields a usable profile | **PASS** | Simulated outage: job FAILED, profile COMPLETED |
| PHQ-9 item-9 positive answer escalates | **PASS** | `safetyFlag=true`; dashboard/profile support card; combined response appends crisis text |
| Mood check-ins feed physical/Mind–Body patterns | **PASS** | `/physical/insights` `moodCheckins: 1` |
| AI-service inbound authentication | **PASS** | 401 without key, 200 with key, health public |
| Future mood timestamps rejected | **PASS** | +2 h POST → 400, no row |
| Dashboard insight label is honest | **PASS** | “Your latest AI insight” on device |
| Combined mental + physical insight | **PASS** | Live endpoint; LLM and deterministic variants; coverage, note, cache |
| Combined output is grounded and non-diagnostic | **PASS** | Strict LLM validation; no invented numbers; Java safety append; live 24/24 checks |
| Generative physical wording | **PASS** | Live `generated_by=llm` direct call; rule fallback; honest UI labels |
| Journal encryption at rest | **PASS** | 3/3 rows `enc:v1:` incl. migrated legacy; 0 plaintext; API plaintext; search decrypts |
| Assessment history UI | **PASS** | Screen + route + entry points; live API 2 rows; widget/route tests |
| Redis caching | **PASS** | 2 keys, TTL 1789/1795 s, second read `cached=true` |
| Internal Keycloak/MinIO/etc. health probes | **PASS** | All 8 containers `healthy` with in-container probes |
| Cross-user isolation | **PASS** | Foreign screening/job/profile/journal → 404; no token → 401 |
| Keycloak login / OIDC | **PASS** | OIDC discovery 200; app session issued |
| Object storage upload/delete | **PASS** | Earlier live upload/delete with user-scoped key |
| On-device capture of new UI | **BLOCKED** | Phone adb endpoint refused; widget/route tests pass |

---

## G. Conclusion

The audit found and fixed everything that could materially mislead, block or
expose a real user on this deployment: silent save confirmations, lost HR
readings on restart, overwritten step totals, 1,000× calorie inflation, a
poisoned sync queue, dishonest sync/capability/distance states, a stranded
“AI pending” profile after terminal failure, a missing safety escalation for a
positive PHQ-9 item 9, plaintext journal storage, and an LLM that described a
days-old mood as “today”.

The previously unimplemented requirements are now delivered and verified
against the running stack: combined mental–physical insight (LLM with
deterministic fallback, Java-owned safety escalation, honest client labels,
Redis cache), optional generative physical wording behind strict validation,
journal encryption at rest with legacy migration, assessment history UI, and
internal health probes for all services.

Every claim above is backed by a test run, a live API/Mongo/Redis observation,
or an on-device screenshot from the earlier pass. The remaining items are
explicitly listed: sleep is blocked by band firmware; journal media is not
covered by the field cipher; search is bounded to 1,000 entries; cached
insights can be up to 30 minutes old; the new UI could not be captured on the
phone because wireless debugging became unavailable; and the safety paragraph
can repeat when the model has already mentioned support.

---

## H. Follow-up pass (2026-10-28)

This pass re-checked the remaining items against the live stack, the physical
phone (`192.168.1.2`, SM-M325F, Android 13) and the real FitPro Watch 8
(`6D:7D:64:37:03:28`, firmware `V15183`). It closes three of the eight remaining
items, replaces one with live evidence, and leaves the rest explicitly blocked.

### H1. New defect found and fixed

| # | Severity | Defect / root cause | Evidence | Change |
|---|---|---|---|---|
| 32 | High (availability) | A physical phone could not reach the backend at all. `AppConfig.apiBaseUrl` is compiled in and defaults to `10.0.2.2`, an emulator-only alias that a phone cannot route, so every request failed with "Unable to reach the server" unless the APK happened to be built with `--dart-define=API_BASE_URL`. Rebuilding was the only remedy. | A rebuilt APK launched on the phone with the default address shows the offline state; the same build with the LAN address loads live data | `ServerEndpoint` resolves the base URL at runtime: a saved per-device address overrides the build default, every request resolves it through the Dio interceptor, and Settings → **Server connection** shows the active address with a reachability test, an edit dialog and a reset. `run-app.sh` still injects the LAN address for builds |
| 33 | Medium (diagnosability) | "Offline — showing your last saved data" appeared with no way to tell which section failed or why. | Observed on the phone while the backend answered every endpoint in ~5 ms | `_markFailure` and the physical `loadToday` catch log the section and the error in debug builds |

Verified live: the rebuilt APK installs, launches, and renders the dashboard,
the safety card and the combined mind–body card from the running backend with no
offline banner. The four screenshots (dashboard, combined card, live heart
rate, Physical Wellness) are retained locally in `docs/screenshots/`; they are
**not published** because they show a real account's name, mood text and
heart-rate reading.

### H2. Remaining items, re-assessed

| # | Previous status | Now | Evidence |
|---|---|---|---|
| 24 | BLOCKED (sleep) | **BLOCKED** | A fresh live sync sent the step request `0x15`/`0x06` after the full preamble and the band answered only with ACKs; no `0x15`/`0x03` sleep frame was emitted. Firmware-side; nothing to fix in the client |
| 25 | Medium (media not sealed) | **FIXED** | Media is now sealed at rest in 1 MiB AES-256-GCM chunks (`MBE2` frame) and served back through a signed, expiring backend URL. Live: uploaded PNG → the stored object is 123 bytes of ciphertext (not the 95-byte PNG), the journal `imageUrl` returns the exact original bytes (HTTP 200, byte-identical), a tampered signature → 403, an expired token → 403. Objects written before the change are recognised and still served |
| 26 | Low (search bounded to newest 1,000) | **FIXED** | Search pages through the caller's whole archive in 500-row chunks instead of reading the newest 1,000, with a 20,000-row per-request ceiling and a warning log when it is reached. A test with a full first chunk of non-matches and an old match on the second page returns it |
| 27 | Low (cache up to 30 min old) | **ACCEPTED, hardened** | The key now also includes `profile.updatedAt()`, heart-rate days, missing sources and the actual insight/recommendation wording, so a changed rule or profile revision misses the cache even inside the TTL (see I1, defect 36). The TTL only matters when nothing changed, where the cached text is still correct |
| 28 | Low (no on-device capture) | **PARTLY FIXED** | The combined mind–body card, the rebuilt dashboard, the live heart-rate screen and the Physical Wellness hub were captured on the physical phone; the images stay local (`docs/screenshots/`) because they contain personal health data. The assessment-history screen still has no capture: wireless debugging dropped again mid-session (all ports refused, no mDNS) |
| 29 | Medium (safety text could repeat) | **FIXED** | The escalation is split into the reason and the crisis line. Java still always guarantees the crisis line, so the model cannot suppress escalation, but a sentence whose point the model already made is no longer repeated. Covered by three tests, including "the model already says to reach out" |
| 30 | Low (Keycloak direct grant) | **NOT A DEFECT** | Unchanged; direct grant stays disabled by design |
| 31 | BLOCKED (physical LLM wording) | **BLOCKED** | Correct sparse-data behaviour; no data was fabricated to force `aiEnhanced=true` |

### H3. Bluetooth connect — verified on hardware, no defect found

The connect path was exercised live against the real band rather than with a
fake transport:

- `connect()` → `onConnectionStateChange CONNECTED`, GATT service discovery
  completed in **8.2 s** (inside the 25 s connect timeout the earlier pass
  introduced; the old 10 s window would have failed here).
- The full preamble ran and was answered: `0x12`/`0x0a`, clock sync,
  `0x12`/`0x01`, `0x1a`/`0x0a`, `0x1a`/`0x0c`, `0x12`/`0x15`, `0x12`/`0xff`,
  `0x1a`/`0x01`, `0x1a`/`0x0f`, `0x1a`/`0x10`, `0x20`/`0x02` (device info —
  `V15183`, battery 54 %) and `0x15`/`0x06` (step history) — every frame ACKed.
- Live heart rate from the heart-rate screen: Start → `0x12`/`0x18` ACKed →
  `0x15`/`0x0e` sample → **74 bpm** rendered in the app and counted as
  `1 samples · 74–74 bpm`.
- The only user-visible gap is honest and unchanged: the band only replays new
  history, so a sync with no new movement reports "connected but reported no new
  health data" instead of inventing a reading.

### H4. Gates re-run after this pass

| Gate | Result |
|---|---|
| Backend `mvn test` | **572 passed, 0 failed, 0 errors, 0 skipped** (re-run after section I) |
| Flutter `flutter test` | **364 passed, 1 skipped, 0 failed** |
| Android `:app:testDebugUnitTest` | **41 passed, 0 failed** |
| AI service `pytest` | **164 passed** |
| Live media round trip | uploaded PNG sealed in the bucket (`MBE2`, 123 bytes) and served back byte-identical; tampered/expired URL → 403 |
| Live services | backend `/actuator/health` 200, AI `/health` 200, combined-insight 200 |

### H5. Still open

- Sleep frames (24) and the physical LLM wording path (31) remain blocked by
  band firmware and by correct sparse-data behaviour respectively.
- The assessment-history screen (28, remainder) has no on-device capture because
  the phone's wireless debugging endpoint dropped mid-session. Capturing it is a
  two-minute job once the phone accepts `adb` again.
- Item 27 is an accepted trade-off, and item 30 is not a defect.

---

## I. Final consolidation pass (2026-10-30)

This pass closed the loose ends left by section H, re-ran every gate, and
prepared the repository for a clean push. No wellness record was rewritten:
all write checks use the throwaway account, and the main account was only read.

### I1. Defects found and fixed

| # | Severity | Defect / root cause | Evidence | Change | Regression |
|---|---|---|---|---|---|
| 34 | High (feature availability) | Journal media uploads and deletes used the build-time `AppConfig.apiBaseUrl`, not the runtime `ServerEndpoint.current`. On a phone that had corrected the server address in Settings, text requests worked while photo/audio/video upload still went to the unreachable emulator alias. | Upload failed while the same app loaded combined insight and physical data from the corrected host; the service concatenated `AppConfig.apiBaseUrl` directly | Both the upload POST and the delete now resolve `ServerEndpoint.current` at call time, like every other API call | `flutter analyze` clean on both touched files; media round-trip verified live against the backend |
| 35 | Medium (recoverability) | The login screen had no way to reach Server settings. A build whose compiled default address is unreachable showed "Unable to reach the server" and the user could not sign in to reach Settings, so the app was unusable without a rebuild. | Rebuilt default build on the phone: login failed with a network error and no correction path | A **Server settings** link on the login screen pushes `/settings`, so the address can be fixed before authentication | Login widget/route tests still pass; link analysed clean |
| 36 | Low (staleness) | The combined-insight cache fingerprint hashed only ids for physical insights and recommendations. A rule whose wording or values changed (e.g. step total inside a summary) kept serving the old text until the 30-minute TTL. | Same key produced after the rule text changed; unit test now captures both fingerprints | Fingerprint also hashes `profile.updatedAt()`, heart-rate days, missing sources, insight title/summary/severity and recommendation title/description/category/source | `CombinedInsightServiceTest` fingerprint test passes; live combined endpoint still 200 |
| 37 | Medium (safety) | If the model named self-harm but did not advise outreach, the escalation added only the crisis line. The narrative explained the cause but never asked the reader to reach out. | Reproduced with a model payload that mentions self-harm without "reach out"; the resulting escalation had no actionable request | Escalation is split into reason, outreach and crisis. Java and the AI service both add outreach when missing, and reuse the cause-free sentence when the model already named the cause, so the cause is not repeated | New backend test `escalationStillAsksForOutreachWhenTheModelOnlyNamesTheCause`; new AI test `test_safety_escalation_never_drops_outreach_when_cause_is_named` |
| 38 | Low (diagnosability) | An unknown route (including a trailing slash such as `/api/v1/wellness-profile/`) was answered `500 INTERNAL_ERROR`. A mistyped URL therefore looked like a backend outage. | `GET /api/v1/wellness-profile/` → 500; logs show `NoResourceFoundException` reaching the generic handler | `GlobalExceptionHandler` maps `NoResourceFoundException` to `404 NOT_FOUND` | New `GlobalExceptionHandlerTest`; valid `/api/v1/wellness-profile` still 200 |

The earlier "`/api/v1/wellness/profile` returns 500" note was a wrong path in the
audit script. The real endpoint is `/api/v1/wellness-profile`, which returns 200
with the stored main-account profile. Defect 38 fixes the misleading 500 that the
wrong path produced.

### I2. Model artifact policy

`vit_fer_fp16.tflite` (171.9 MB) is intentionally **not** committed to this
public repository:

- GitHub rejects files above 100 MB, and Git LFS is not installed on this host.
- The upstream weights (`motheecreator/vit-Facial-Expression-Recognition`) have
  **no recorded license**, so redistributing them publicly is not justified.
- Both copies (`app/assets/models/` and `ai-service/app/models/`) are listed in
  `.gitignore`; `app/assets/models/vit_fer_manifest.json` stays tracked and
  carries the SHA-256 for verifying a locally provisioned copy.

Provision the file locally before building the Flutter app or the AI image; the
existing Dockerfile and `docs/fer-migration.md` describe the expected path.

The four on-device screenshots and the patent drafts are also not part of this
push. The screenshots show a real account's name, mood text and heart rate; the
patent drafts are unpublished filing material. Both remain untracked locally.

### I3. Gates re-run on 2026-10-30

| Gate | Result |
|---|---|
| Backend `mvn test` | **572 passed, 0 failed, 0 errors, 0 skipped** |
| Flutter `flutter test` | **364 passed, 1 skipped, 0 failed** |
| Android `:app:testDebugUnitTest` | **41 passed, 0 failed** |
| AI service `pytest` | **164 passed, 1 warning** (Qdrant compatibility warning only) |
| `flutter analyze` on the two changed Dart files | **No issues found** |
| Live backend `/actuator/health` | **200 UP** |
| Live AI `/health` | **200**, `emotion_model=loaded`, `text_analyzer=transformer` |
| Live Keycloak discovery | **200** |
| Live combined insight | **200** (`generatedBy=llm`, safety escalation appended) |
| Live physical insights | **200** (`sufficientData=false`, 4 activity / 0 sleep / 3 hydration / 2 mood) |
| Live main profile | **200** at `/api/v1/wellness-profile` |

### I4. Remaining limitations (unchanged and honest)

1. **Sleep / sleep stages — BLOCKED.** The firmware ACKs the request but never
   emits a `0x15/0x03` frame. No sleep value is invented.
2. **Physical LLM wording — BLOCKED by sparse data.** The main account has no
   sleep and few activity days, so the rule engine correctly reports
   `aiEnhanced=false`. Forcing a model sentence would fabricate evidence.
3. **Assessment-history screenshot — NOT CAPTURED.** Wireless debugging on the
   phone stopped accepting connections again (ports closed, no mDNS), so the
   history screen remains covered only by widget/route tests.
4. **FER model weights — NOT IN GIT.** Locally provisioned, per I2.
5. **On-device FER performance — NOT MEASURED.** Host latency only; no phone
   load time, FPS or memory figure.
6. **Release packaging — OPEN.** The uncompressed model makes the base APK
   ~284 MB; Play Asset Delivery or an install-time fetch is required before Play
   distribution. This is a product decision.
7. **Journal search ceiling.** 20,000 rows per request; beyond that the API says
   more may exist and logs a warning. Acceptable for the expected archive size.

### I5. Publication

This pass was committed as **`293deb1`** (documentation follow-up `923737c`)
and pushed to the public branch
[`sheikabdullah/corefeature`](https://github.com/SHEIKABDULLAHPM/AI-Mental-Health-Screening-App/commit/293deb147567ef60220e35822822b2588b4cb857).
The remote tree contains 884 files and was checked to contain no FER weights,
no personal screenshots, no patent drafts and no secret material. All changes
remain single-database and ownership-scoped; no multi-tenancy work was done.
