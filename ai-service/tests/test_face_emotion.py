"""Tests for server-side facial emotion inference (vit_fer_fp16.tflite, ViT-B/16).

These tests run against the REAL model artifact — no mocked inference.
"""

from __future__ import annotations

import io
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from app.core.mood.face_emotion import (
    MODEL_NUM_CLASSES,
    MODEL_TENSOR_LAYOUT,
    VIT_FER_7_LABELS,
    FaceEmotionAnalyzer,
    FaceEmotionError,
    get_face_emotion_analyzer,
)

MODEL_PATH = (
    Path(__file__).resolve().parent.parent
    / "app"
    / "models"
    / "vit_fer_fp16.tflite"
)

# The same golden crops the Flutter test uses. Present in the monorepo; the
# parity test skips rather than fails if this service is tested standalone.
GOLDEN_DIR = Path(__file__).resolve().parents[2] / "app" / "test" / "fer_vit_golden"


def _make_face_jpeg(size: int = 160, flat: bool = False) -> bytes:
    """Build a synthetic face-crop JPEG with enough texture to pass gates."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(42)
    if flat:
        arr = np.full((size, size, 3), 128, dtype=np.uint8)
    else:
        base = np.linspace(40, 210, size, dtype=np.float32)
        grad = np.tile(base, (size, 1))
        noise = rng.normal(0, 25, (size, size)).astype(np.float32)
        ch = np.clip(grad + noise, 0, 255).astype(np.uint8)
        arr = np.stack([ch, ch, ch], axis=-1)
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, format="JPEG")
    return buf.getvalue()


@pytest.fixture(scope="module")
def analyzer() -> FaceEmotionAnalyzer:
    return FaceEmotionAnalyzer(MODEL_PATH).load()


# ── Model loading ───────────────────────────────────────────────────────


def test_model_artifact_exists():
    assert MODEL_PATH.is_file(), "vit_fer_fp16.tflite must ship in app/models"


def test_model_loads_and_validates_tensors(analyzer):
    assert analyzer.loaded is True


def test_label_count_must_match_classes():
    with pytest.raises(FaceEmotionError) as exc_info:
        FaceEmotionAnalyzer(MODEL_PATH, labels=["happy", "sad"]).load()
    assert exc_info.value.code == "label_mismatch"


def test_missing_model_fails_clearly(tmp_path):
    with pytest.raises(FaceEmotionError) as exc_info:
        FaceEmotionAnalyzer(tmp_path / "nope.tflite").load()
    assert exc_info.value.code == "model_missing"


def test_singleton_loads_once():
    first = get_face_emotion_analyzer()
    second = get_face_emotion_analyzer()
    assert first is second
    assert first.loaded is True


# ── Preprocessing / input validation ────────────────────────────────────


def test_preprocess_matches_model_input(analyzer):
    batch = analyzer._preprocess(_make_face_jpeg())
    # NCHW for the ViT. MobileNetV3 was (1,224,224,3); getting this wrong is
    # a hard shape error at set_tensor time, not a silent quality loss.
    assert batch.shape == (1, 3, 224, 224), "ViT input must be NCHW"
    assert batch.dtype.name == "float32"
    assert batch.min() >= -1.0 and batch.max() <= 1.0  # mean/std 0.5 range


def test_tensor_layout_constant_is_nchw():
    assert MODEL_TENSOR_LAYOUT == "NCHW"


def test_preprocess_is_channel_major(analyzer):
    """Transposing the tensor back must reproduce the resized RGB image."""
    import numpy as np
    from PIL import Image

    batch = analyzer._preprocess(_make_face_jpeg())
    hwc = np.transpose(batch[0], (1, 2, 0))
    # Same spatial size the analyzer resized to, with 3 channels last.
    assert hwc.shape == (224, 224, 3)
    # The quality gate runs on HWC 0-255; the tensor is the normalized form,
    # so undoing x/127.5 - 1 as (x+1)*127.5 must land back in byte range.
    restored = (hwc + 1.0) * 127.5
    # JPEG is lossy, so allow a small overshoot; the point is the layout.
    assert -8.0 <= restored.min() and restored.max() <= 263.0


def test_invalid_image_rejected(analyzer):
    with pytest.raises(FaceEmotionError) as exc_info:
        analyzer.predict(b"not-an-image-at-all")
    assert exc_info.value.code == "invalid_image"


def test_too_small_crop_rejected(analyzer):
    with pytest.raises(FaceEmotionError) as exc_info:
        analyzer.predict(_make_face_jpeg(size=16))
    assert exc_info.value.code == "face_too_small"


def test_flat_crop_rejected(analyzer):
    with pytest.raises(FaceEmotionError) as exc_info:
        analyzer.predict(_make_face_jpeg(flat=True))
    assert exc_info.value.code == "poor_quality"


# ── Inference / output validation (real model) ──────────────────────────


def test_inference_returns_valid_structured_result(analyzer):
    result = analyzer.predict(_make_face_jpeg())
    assert len(result.probabilities) == MODEL_NUM_CLASSES
    assert set(result.probabilities) == set(VIT_FER_7_LABELS)
    assert abs(sum(result.probabilities.values()) - 1.0) < 0.01
    assert all(0.0 <= p <= 1.0 for p in result.probabilities.values())
    assert 0.0 <= result.confidence <= 1.0
    assert 0.0 <= result.margin <= 1.0
    # No legacy 8-class names may leak out of this service again.
    assert result.emotion in (*VIT_FER_7_LABELS, "uncertain")
    assert result.emotion not in ("happiness", "sadness", "contempt", "angry")
    assert result.model_version == "vit-fer-7"
    payload = result.to_response()
    assert {
        "emotion",
        "confidence",
        "margin",
        "probabilities",
        "model_version",
        "analysis_version",
    } <= set(payload)


def test_low_confidence_returns_uncertain_not_forced():
    strict = FaceEmotionAnalyzer(MODEL_PATH, confidence_threshold=1.0).load()
    result = strict.predict(_make_face_jpeg())
    assert result.emotion == "uncertain"


def test_nan_output_rejected(analyzer):
    import numpy as np

    with pytest.raises(FaceEmotionError) as exc_info:
        analyzer._decode(np.full((1, 7), float("nan"), dtype=np.float32))
    assert exc_info.value.code == "invalid_output"


def test_wrong_shape_output_rejected(analyzer):
    import numpy as np

    with pytest.raises(FaceEmotionError) as exc_info:
        analyzer._decode(np.zeros((1, 8), dtype=np.float32))
    assert exc_info.value.code == "invalid_output"


def test_concurrent_inference_is_consistent(analyzer):
    payload = _make_face_jpeg()

    def run(_: int) -> str:
        r = analyzer.predict(payload)
        return f"{r.emotion}:{r.confidence}"

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(run, range(8)))
    assert len(set(results)) == 1  # no race-induced divergence


# ── API contract ────────────────────────────────────────────────────────


def test_face_endpoint_contract():
    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    resp = client.post(
        "/api/v1/mood/face",
        files={"file": ("crop.jpg", _make_face_jpeg(), "image/jpeg")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert {
        "emotion",
        "confidence",
        "margin",
        "probabilities",
        "model_version",
        "analysis_version",
    } <= set(body)
    assert 0.0 <= body["confidence"] <= 1.0
    assert "traceback" not in resp.text.lower()


def test_face_endpoint_rejects_non_image():
    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    resp = client.post(
        "/api/v1/mood/face",
        files={"file": ("x.txt", b"hello", "text/plain")},
    )
    assert resp.status_code == 400


def test_face_endpoint_rejects_tiny_crop():
    from fastapi.testclient import TestClient

    from app.main import app

    client = TestClient(app)
    resp = client.post(
        "/api/v1/mood/face",
        files={"file": ("tiny.jpg", _make_face_jpeg(size=16), "image/jpeg")},
    )
    assert resp.status_code == 422


# ── Class order (the silent-corruption guard) ───────────────────────────


def test_class_order_matches_the_models_id2label():
    # This is NOT the FER2013 order. Positions 5/6 are neutral, sad here and
    # sad, surprise in FER2013. If someone "corrects" this to FER2013 the
    # model still runs and three of seven classes come out mislabelled.
    assert VIT_FER_7_LABELS == (
        "anger",
        "disgust",
        "fear",
        "happy",
        "neutral",
        "sad",
        "surprise",
    )
    assert VIT_FER_7_LABELS[4] == "neutral"
    assert VIT_FER_7_LABELS[5] == "sad"
    assert VIT_FER_7_LABELS[6] == "surprise"


def test_configured_labels_match_the_module_default():
    from app.config import settings

    assert tuple(settings.emotion_labels) == VIT_FER_7_LABELS


def test_config_defaults_point_at_the_vit():
    from app.config import settings

    assert settings.emotion_model_path.endswith("vit_fer_fp16.tflite")
    assert settings.emotion_model_version == "vit-fer-7"
    assert settings.emotion_normalization == "mean_std_0.5"


# ── Logits decoding ────────────────────────────────────────────────────


def test_logits_are_softmaxed(analyzer):
    """The ViT emits logits, not probabilities; decode must normalize."""
    import numpy as np

    # A raw logit vector as the model actually returns (sum != 1).
    logits = np.array([[4.8936, -2.5367, 1.9253, -2.3123, -0.632, -0.3134,
                        -2.2132]], dtype=np.float32)
    assert abs(float(logits.sum()) - 1.0) > 1e-3, "fixture must not be a probability vector"
    result = analyzer._decode(logits)
    assert abs(sum(result.probabilities.values()) - 1.0) < 0.01
    assert result.emotion == "anger"
    assert abs(result.confidence - 0.9407) < 1e-3


def test_already_normalized_output_is_not_double_softmaxed(analyzer):
    import numpy as np

    probs = np.array([[0.7, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]], dtype=np.float32)
    result = analyzer._decode(probs)
    assert abs(sum(result.probabilities.values()) - 1.0) < 0.01
    assert result.emotion == "anger"
    assert abs(result.confidence - 0.7) < 1e-3


# ── Margin gate ────────────────────────────────────────────────────────


def test_ambiguous_top1_returns_uncertain(analyzer):
    """High confidence but a near-tied runner-up must not be forced."""
    import numpy as np

    # 0.45 / 0.44 -> confident-looking top-1, essentially a coin flip.
    ambiguous = np.array([[0.45, 0.44, 0.03, 0.03, 0.02, 0.02, 0.01]],
                         dtype=np.float32)
    result = analyzer._decode(ambiguous)
    assert result.emotion == "uncertain"
    assert result.margin < 0.10


def test_decisive_top1_passes_both_gates(analyzer):
    import numpy as np

    # Index 0 is "anger" in this vocabulary.
    decisive = np.array([[0.82, 0.06, 0.03, 0.03, 0.02, 0.02, 0.02]],
                         dtype=np.float32)
    result = analyzer._decode(decisive)
    assert result.emotion == "anger"
    assert result.margin == pytest.approx(0.76, abs=0.01)


def test_margin_gate_rejects_even_at_high_confidence():
    """The regression the margin gate exists for."""
    import numpy as np

    loose = FaceEmotionAnalyzer(
        MODEL_PATH, confidence_threshold=0.0, margin_threshold=0.10
    ).load()
    tied = np.array([[0.5001, 0.4999, 0.0, 0.0, 0.0, 0.0, 0.0]], dtype=np.float32)
    assert loose._decode(tied).emotion == "uncertain"


def test_thresholds_are_not_lowered_for_hit_rate():
    from app.config import settings

    # Justified by the 175-image validation replay; lowering these to inflate
    # detection counts is explicitly out of contract.
    assert settings.emotion_confidence_threshold == 0.6
    assert settings.emotion_margin_threshold == 0.10


# ── Cross-layer parity with the Flutter client ─────────────────────────


@pytest.mark.skipif(
    not (GOLDEN_DIR / "reference.json").is_file(),
    reason="shared golden fixture not available (standalone checkout)",
)
def test_matches_flutter_golden_reference(analyzer):
    """Same crops, same expected probabilities as the Dart test.

    This is the guard against the two implementations drifting apart: the
    on-device path and this service must preprocess identically and agree on
    every class.
    """
    import json

    import numpy as np
    from PIL import Image

    ref = json.loads((GOLDEN_DIR / "reference.json").read_text())
    classes = ref["classes"]
    probs = ref["probs"]
    assert tuple(classes) == VIT_FER_7_LABELS, "class order must match the model"

    worst = 0.0
    matched = 0
    total = 0
    for pos in range(21):
        crop = GOLDEN_DIR / f"crop_{pos:02d}.raw"
        if not crop.is_file():
            continue
        arr = np.fromfile(crop, dtype=np.uint8).reshape(224, 224, 3)
        buf = io.BytesIO()
        Image.fromarray(arr, "RGB").save(buf, format="PNG")

        result = analyzer.predict(buf.getvalue())
        expected = np.asarray(
            probs[f"{classes[ref['true'][pos]]}_{pos}"], dtype=np.float64
        )
        got = np.asarray([result.probabilities[c] for c in classes],
                         dtype=np.float64)
        assert got.shape == (7,) and expected.shape == (7,)
        worst = max(worst, float(np.abs(got - expected).max()))
        matched += int(got.argmax() == expected.argmax())
        total += 1

    assert total == 21, "expected all 21 golden crops"
    assert matched == total, f"label agreement {matched}/{total}"
    assert worst < 2e-3, f"probability drift {worst:.2e} exceeds fp16 tolerance"


def test_legacy_mobilenet_normalization_alias_still_normalizes():
    """A stale EMOTION_NORMALIZATION=mobilenet must not crash the service."""
    legacy = FaceEmotionAnalyzer(
        MODEL_PATH, confidence_threshold=0.0, margin_threshold=0.0,
        normalization="mobilenet",
    ).load()
    modern = FaceEmotionAnalyzer(
        MODEL_PATH, confidence_threshold=0.0, margin_threshold=0.0,
        normalization="mean_std_0.5",
    ).load()

    png = _make_face_jpeg(160)
    a = legacy._preprocess(png)
    b = modern._preprocess(png)
    assert np.array_equal(a, b), "alias must be arithmetically identical"
    assert a.shape == (1, 3, 224, 224) and a.dtype == np.float32
    assert abs(float(a.min()) + 1.0) < 0.25 and abs(float(a.max()) - 1.0) < 0.25


def test_unknown_normalization_is_rejected():
    bad = FaceEmotionAnalyzer(MODEL_PATH, normalization="zscore").load()
    with pytest.raises(FaceEmotionError) as exc:
        bad._preprocess(_make_face_jpeg(160))
    assert exc.value.code == "config_error"
