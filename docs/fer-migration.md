# Facial emotion pipeline — migration record (vit-fer-7)

Replaces `synora-fer` (a 48,776-param depthwise-separable CNN) with a
seven-class ViT-B/16. The old model failed its own quality gates
(macro-F1 0.5499, worst-class recall 0.2941 against thresholds of
0.58 / 0.35) and collapsed to two visible classes in the camera flow.

Status: **validated, device verification outstanding.** The model, the
conversion, the accuracy and the confidence gates are all measured and
recorded below. What is *not* done is on-device benchmarking — no device
was reachable — and packaging is oversized. See §8.

## 1. Architecture

```
ANDROID (on-device, no raw frames leave the phone)
Camera (ML Kit: box + landmarks + tracking)
→ FaceQualityGate (size / yaw-pitch / brightness / contrast / Laplacian blur / eye-presence)
→ Eye-similarity alignment → 224x224 interleaved RGB
→ mean/std 0.5 normalization, NCHW float32 ([1,3,224,224])
→ vit-fer-7 (fp16 TFLite, GPU delegate w/ CPU fallback + warm-up check)
→ confidence + top1/top2 margin gate (0.60 / 0.10)
→ Temporal fusion (quality-weighted EMA, vote agreement ≥0.75, ≥4 frames)
→ PREDICTED / UNCERTAIN / quality-gate status (never forced, never silent)
→ Structured result → mood check-in (best-effort persistence)
```

Frame handling: the tightly packed NV21 buffer is converted to upright
interleaved RGB **in ML Kit's coordinate space**, so the face box and eye
landmarks index the same pixels the model sees. Luminance for the quality
gate still comes from the Y plane; chroma is what the model needs and is
what the Y plane throws away.

### 1a. Two colour bugs found while testing the RGB path (fixed)

The NV21 → RGB path had **no direct test coverage** — existing tests stopped
at `packNv21` and at the aligner, so nothing ever drove the two together.
Adding that missing test surfaced two real defects, both of which would
have silently degraded every prediction:

1. **Red/blue channel swap.** `packNv21` writes the interleaved chroma
   plane as V,U (true NV21), but `nv21ToRgb` read the same bytes back as
   U,V. Producer and consumer disagreed, so every frame reaching the model
   had its red and blue channels transposed. This is invisible to a
   quality gate because luminance is unchanged by a channel swap — only
   the colour casts are wrong. Fixed, and pinned by two round-trip tests
   that drive `packNv21` → `nv21ToRgb` from Android's real plane order.
2. **Full-range matrix on limited-range data.** The Android camera HAL
   emits studio-swing NV21 (Y ∈ [16, 235]). The code applied the
   full-range inverse, which lifts blacks by ~16 and compresses whites by
   ~20 across the whole crop — a systematic contrast shift the model never
   saw in training. The code comment had drifted to say "full-range" while
   the function's own doc comment still promised studio swing. Fixed to
   the studio-swing coefficients, with tests asserting the black/white
   points land on 0/255 and that the grey axis stays neutral.

The grey-axis test is the load-bearing one: any mistyped per-channel
coefficient breaks R=G=B, so the YUV matrix cannot be edited without the
suite noticing.

Privacy: no frame, crop or base64 blob is logged. The previous build
printed a base64 face crop into logcat every 12 frames under
`FER_CROP`; that is deleted, and `kFerDiagnostics` is now `false` and emits
scalars only.

## 2. Model (shipped)

- `vit-fer-7` v1.0.0, ViT-B/16 (12 layers, 12 heads, hidden 768, 197
  patches, GAP + fc + softmax), 85,804,039 parameters.
- Upstream: `motheecreator/vit-Facial-Expression-Recognition`. **The
  upstream repository has no model card, so its FER training set is
  unknown** and must not be assumed to match the independent validation
  set below. The 7-class label order is the model's own `id2label`.
- Classes (canonical): anger, disgust, fear, happy, neutral, sad, surprise.
  Presentation mapping is versioned as `camera-emotion-map-v2`
  (disgust shares the 'Irritated' tag; the canonical class is always
  preserved in `emotionScores` and the backend event).
- Production artifact: `vit_fer_fp16.tflite`, 171.9 MB,
  SHA-256 `16aa6d6dea8477846a6e9ef87d0d89a8c0d815fa219bd2ad45fecd379643cda1`,
  float32 input/output, fp16 weights.

## 3. Measured results

Validation set: 175 images, 25 per class, seed 42, drawn from the public
`wallbreaker01/Facial-Expression-Detection` test split. Balanced by
construction, so the confusion matrix is per-class counts and accuracy is
not skewed by class frequency. It is a small stratified sample — treat
per-class metrics as carrying roughly ±0.07 of sampling error.

| Metric | Value |
|---|---|
| Accuracy | 0.8686 (152/175) |
| Macro F1 | 0.8690 |
| Worst-class recall | 0.760 (fear) |
| Quality gates | macro-F1 ≥0.58 **PASS**, worst recall ≥0.35 **PASS** |
| Host CPU latency | ~137 ms/image, batch 1 |

Per-class precision / recall / F1:

| class | P | R | F1 |
|---|---|---|---|
| anger | 0.889 | 0.960 | 0.923 |
| disgust | 1.000 | 0.920 | 0.958 |
| fear | 0.731 | 0.760 | 0.745 |
| happy | 0.880 | 0.880 | 0.880 |
| neutral | 0.778 | 0.840 | 0.808 |
| sad | 0.952 | 0.800 | 0.870 |
| surprise | 0.885 | 0.920 | 0.902 |

Confusion matrix (rows = truth, columns in canonical order):

```
[24, 0, 1, 0, 0, 0, 0]   anger
[ 0,23, 1, 0, 1, 0, 0]   disgust
[ 2, 0,19, 0, 2, 1, 1]   fear
[ 0, 0, 1,22, 2, 0, 0]   happy
[ 0, 0, 0, 3,21, 0, 1]   neutral
[ 1, 0, 2, 0, 1,20, 1]   sad
[ 0, 0, 2, 0, 0, 0,23]   surprise
```

## 3a. Conversion evidence (§ "never assume")

onnx2tf's direct float16 and SavedModel paths are both broken for this
graph. The shipped artifact comes from an exact Keras reimplementation
of the PyTorch graph.

| Step | Agreement | Max abs prob diff |
|---|---|---|
| PyTorch → ONNX | 175/175 | 6.23e-06 |
| PyTorch → Keras reimplementation | 175/175 | 7.39e-06 |
| PyTorch → fp16 TFLite | 175/175 | 9.22e-04 (mean 1.47e-04) |

Rejected alternatives, recorded rather than hidden:

- **int8 post-training quantization**: 23/175 label agreement with the
  float model, 21/175 accuracy (12.0%), macro-F1 0.104, happy recall 0.000.
  Catastrophic, so the 171.9 MB fp16 artifact ships instead.
- **onnx2tf float16**: fails allocating an FP16 input at `CONV_2D`.
- **onnx2tf SavedModel**: fails on `Cannot reshape a tensor with 151296
  elements to shape []`.

## 3b. Calibration and the confidence gate

Temperature was re-fitted on the new model by grid search over
T ∈ [0.5, 8.0] against the 175 validation vectors. NLL minimised at
T = 0.96 (0.34343) versus 0.34389 at T = 1.0 — no meaningful improvement
over an unscaled softmax, and ECE was slightly *better* at T = 1.0. So
**T = 1.0 is retained**. The old model's T = 0.8278 is measurably worse
here (NLL 0.34962) and was rejected rather than carried over.

Measured behaviour of the shipped 0.60 / 0.10 gate on the validation set:

- Single-frame emission rate **90.3%**.
- **Every one of the seven classes reaches PREDICTED** on its own
  correctly-classified, sufficiently-confident data. This is the direct
  regression test for the old "only happy and neutral ever surface" bug.
- Gating *raises* precision: raw argmax accuracy 152/175 (86.9%) versus
  146/158 (92.4%) on the emitted subset.
- A near-uniform distribution stays UNCERTAIN, and a decisive minority
  class is never suppressed.

`test/vit_gate_coverage_test.dart` locks all of this in, including the
threshold values themselves, so the gate cannot be loosened later to
manufacture a better-looking number.

## 4. Tests

- **Flutter: 173 pass, 1 skip, 2 pre-existing failures.** The 2 failures
  (`feature_audit_test.dart`, `ui_audit_test.dart`) are unmodified from
  pristine HEAD and fail on `ProviderNotFoundException` for
  `MoodController`; they are audit-harness provider wiring, not the
  emotion pipeline, and the camera screen is not exercised by either.
- The skip is the TFLite interpreter run: the host test VM has no
  `libtensorflowlite_c-linux.so`, so golden parity defers to device. The
  same fixture *was* verified out-of-band against the shipped fp16
  bytes — 21/21 label agreement, 9.22e-04 max diff.
- `test/vit_golden_parity_test.dart` re-derives the tensor in Dart from
  the stored uint8 crops and asserts min/max/sum against the values
  Python used, which catches a channel swap, a layout change or a
  different normalization — none of which hand-written unit vectors
  would catch.
- `test/fer_frame_geometry_test.dart` covers the NV21 -> RGB path end to end,
  including the `packNv21` -> `nv21ToRgb` round trip that caught the
  red/blue swap, the studio-swing black/white points, the neutral grey
  axis, out-of-gamut clamping, and upright rotation at 0/90/180/270.
- Fixtures live in `test/fer_vit_golden/` (21 crops, 3 per class, plus
  the full 175-vector validation set). **Not** in `test/testdata/`,
  because that directory is `root:root` and unwritable; the new files had
  to go somewhere writable.

## 5. Removed

- `app/assets/models/model_int8.tflite` (the Synora artifact) and
  `synora_fer_manifest.json` — **deleted.** The Flutter side no longer
  references them and they are gone from the tree.
- `ai-service/app/models/mobileNetV3_emotion.tflite` — **deleted.** The
  FastAPI service now runs the same ViT artifact as the device. Removed only
  after `tests/test_face_emotion.py` reproduced the 21/21 golden parity
  against the ViT; see §6.
- `ai-service/requirements.txt` and all live config/env/compose entries
  pointing at the old server model — repointed to
  `app/models/vit_fer_fp16.tflite`.
- `test/testdata/fer_golden/` — the 32 Synora golden tensors and a
  duplicate 76 KB model copy. Root-owned; still on disk, see §8.
- `test/golden_parity_test.dart` and `test/fer_gate_coverage_test.dart`
  — both were bound to the Synora artifact; replaced by
  `test/vit_golden_parity_test.dart` and `test/vit_gate_coverage_test.dart`.
- `FER_CROP` base64 face-crop logging.
- The 8-class display-name map, which would have silently shown users a
  bare "happy" once the model started emitting 7 different ids. Display
  names now live beside `kFerClasses` with a test asserting they stay
  complete and contain no stale classes.

## 6. Backend — both surfaces migrated to the same 7-class contract

The earlier state of this document claimed the backend was untouched and
that the label spaces had diverged. **That is no longer true**, and the
claim was wrong on one specific point, so it is corrected here rather than
quietly deleted.

**The `/emotions/events` endpoint was never missing.** The Dart client
points at a base URL that already ends in `/api/v1`, so a call to
`/emotions/events` resolves to the live Spring route
`POST /api/v1/emotions/events`. It had been failing for a different
reason: backend validation still required the 8 Synora classes, so every
valid 7-class payload was rejected. That validation now accepts exactly
the ViT class set.

- **Spring (`backend/`)** — `EmotionClasses.java` is the single source of
  truth for the 7 ids. `CreateEmotionEventRequest` and
  `EmotionEventService` validate against it, and the fixtures were updated
  to match. Full suite: **297 tests, 0 failures, 0 errors, 0 skipped.**
- **FastAPI (`ai-service/`)** — runs the same `vit_fer_fp16.tflite` as the
  device, with the same NCHW input, the same `x/127.5 - 1`
  normalization, the same 0.60 / 0.10 gates, and a matching 7-label
  vocabulary. Full suite: **104 tests, 0 failures.** The service decodes
  the same 21 golden crops as the Dart test and asserts both argmax
  agreement and a <2e-3 probability drift, so the two implementations
  cannot silently drift apart.

**One real bug was found and fixed during this.** The decoder rejected any
output whose values summed to `<= 0` on the assumption that a non-unit sum
meant "garbage". The ViT emits *logits*, and a logits vector for a clean
crop legitimately sums to `-1.19`, so the guard threw
`invalid_output` and the endpoint would have 503'd on correct input. The
decoder now distinguishes probabilities from logits by shape — a
non-negative vector summing to ~1 is treated as already-normalized,
otherwise a max-shifted softmax is applied. There is a regression test
for the negative-sum case.

Label-space change to be aware of downstream: stored historical
`emotionScores` use the old ids (`happiness`, `sadness`, `contempt`,
`angry`); new writes use `happy`, `sad`, no `contempt`, and `anger`.

Separately, and pre-existing: the app POSTs camera results to
`/emotions/events` best-effort, with failures swallowed by a
`debugPrint` so check-in still completes.

## 7. Licenses

Upstream weights are `motheecreator/vit-Facial-Expression-Recognition` on
Hugging Face; **verify their license before distribution** — it was not
recorded during this work. Validation imagery is from
`wallbreaker01/Facial-Expression-Detection`.

## 8. Open items

1. **On-device verification is missing.** No `SM-M325F` was reachable over
   adb, so there is no measured load time, latency, RSS, FPS, delegate
   selection or battery figure for this model. Host CPU is ~137 ms/image,
   which is not a device number. Everything in §3 is host-side. In
   particular, the two colour fixes in §1a are verified only by unit tests,
   **not** against a live camera preview.
2. **Packaging.** The release APK is 283.9 MB and the model is stored
   **uncompressed** (0% deflate — fp16 weights do not compress), so it
   dominates the package outright. Google Play will reject a base APK
   this size; Play Asset Delivery, or moving the weights behind an
   install-time fetch, is required before release. **Not decided here** —
   this is a product/distribution decision, not something to be
   silently changed in code.
3. **Upstream provenance is thin** — no model card, so the training set is
   unknown and the independent validation set is the only real evidence
   about how the model behaves. The model id is `anger`, not `angry`;
   the UI label is "Anger". Wire values are the model's own `id2label`.
   A repo-wide sweep confirms **no** Synora/MobileNet artifact, filename
   or live reference remains on either surface; the only surviving
   mentions of the old ids are in comments and in negative assertions
   that verify their absence.
4. **Three unrelated test failures were repaired here, but two Flutter
   ones remain.** `FutureLetterServiceTest` had 3 genuine
   test-vs-service drift failures (2 missing `delivered` stubs, and
   `markAsOpened` is intentionally idempotent for an already-opened
   letter while its test asserted a 400). Those are fixed; the backend
   suite is fully green. The 2 Flutter audit failures
   (`feature_audit_test.dart`, `ui_audit_test.dart`) are still failing on
   `ProviderNotFoundException` for `MoodController` and were left alone as
   pre-existing and out of scope.
5. **The journal/text emotion path still uses a different label space**
   (`joy`, `sadness`). That is a genuinely separate text model
   (`text_analyzer`), not the facial pipeline, and was intentionally left
   unchanged. It is not a face-model divergence.
6. **GPU delegate unverified.** `GpuDelegateV2` is attempted first with a
   warm-up check and a controlled CPU fallback, but no Mali device has run
   this graph. Treat CPU as the guaranteed path.
7. **Release build needs `--no-tree-shake-icons`**, for a pre-existing
   reason unrelated to this work: `relax_controller.dart:99` and
   `habit_controller.dart:147` call `IconData(codePoint, ...)` with a
   runtime codepoint. Deliberately not refactored here, because changing
   icon resolution in the Relax and Habits features is outside this
   task's scope and risks altering their behaviour.

## 9. Rollback

- App: `git checkout app/lib/features/mood_tracking` plus restoring the
  two root-owned model assets in `app/assets/models/`. The whole
  `domain/emotion/` directory is currently **untracked**, so it is
  deleted by a clean checkout and does not appear in `git diff` — commit
  it before relying on any rollback.
- The class space changed (8 → 7 classes, `happiness` → `happy`,
  `sadness` → `sad`, `contempt` removed). Any stored historical
  `emotionScores` use the old labels; analytics must handle both or be
  backfilled. This is a breaking change to the mood data contract.
