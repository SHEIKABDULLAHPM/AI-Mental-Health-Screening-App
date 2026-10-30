"""Server-side facial emotion inference backed by vit_fer_fp16.tflite.

Responsibilities (inference only — no routing, auth, or business logic here):
- Load the TFLite/LiteRT model ONCE and reuse the interpreter.
- Preprocess a face-crop image to the model's exact input tensor.
- Run inference under a lock (TFLite interpreters are not thread-safe).
- Validate and decode the output tensor into a structured result.
- Apply confidence AND margin thresholds (low confidence or an ambiguous
  top-1/top-2 pair -> "uncertain", never a forced label).

Face DETECTION stays on-device (Flutter + ML Kit, existing architecture).
The server only classifies the face crop it receives, plus cheap crop-quality
gates (dimensions, brightness, contrast). No face recognition is performed.

Model facts (verified against the artifact, not assumed):
- Backbone: ViT-B/16, 85.8M params, float32 input/output, fp16 weights.
- Input tensor:  [1, 3, 224, 224] float32 — **NCHW, not NHWC**. Feeding
  NHWC raises a dimension mismatch, which is the intended loud failure.
- Output tensor: [1, 7] float32 **logits** (they do NOT sum to 1); a softmax
  is applied during decode.
- Normalization: x/127.5 - 1 (equivalent to mean/std 0.5, range [-1, 1]).

The previous model was MobileNetV3 with NHWC input and softmaxed probabilities.
Both of those assumptions are gone; do not reintroduce them.

Label order cannot be read from the TFLite artifact (no embedded metadata), so
it is pinned to the model's own `id2label` and MUST stay in this order.
Note that positions 5 and 6 differ from the canonical FER2013 order
(sad, surprise, neutral) — a mismatch here silently mislabels 3 of 7 classes.
Override via EMOTION_LABELS only if the training order ever changes.
"""

from __future__ import annotations

import io
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from app.logging import get_logger

log = get_logger(__name__)

# ── Centralized emotion-label configuration ─────────────────────────────
# The vit-fer-7 model's own id2label order. SINGLE SOURCE OF TRUTH: the
# endpoint, fusion, and tests all import from here, and the Flutter client
# and Spring backend use the identical vocabulary and ordering.
#
# This is NOT the FER2013 order (which is angry, disgust, fear, happy, sad,
# surprise, neutral). Positions 5/6 differ: here they are neutral, sad.
# Reordering this tuple mislabels three classes with no runtime error.
VIT_FER_7_LABELS: tuple[str, ...] = (
    "anger",
    "disgust",
    "fear",
    "happy",
    "neutral",
    "sad",
    "surprise",
)

MODEL_INPUT_HEIGHT = 224
MODEL_INPUT_WIDTH = 224
MODEL_INPUT_CHANNELS = 3
MODEL_NUM_CLASSES = 7
MODEL_VERSION_DEFAULT = "vit-fer-7"
ANALYSIS_VERSION = "2.0"

# Tensor layout of the model input. The ViT is NCHW; MobileNetV3 was NHWC.
MODEL_TENSOR_LAYOUT = "NCHW"

# Canonical emotion -> suggested mood (same mapping as the client).
_EMOTION_TO_MOOD = {
    "happy": "happy",
    "neutral": "calm",
    "sad": "low",
    "anger": "stressed",
    "surprise": "okay",
    "fear": "stressed",
    "disgust": "low",
    "uncertain": "okay",
    "unknown": "okay",
}

# Cheap crop-quality gates (face detection itself stays on-device).
_MIN_CROP_SIDE_PX = 48
_MIN_BRIGHTNESS = 12.0
_MAX_BRIGHTNESS = 243.0
_MIN_CONTRAST = 6.0  # stddev of luma; below ~= flat/uniform image


class FaceEmotionError(Exception):
    """Controlled inference failure with a machine-readable code."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass
class FaceEmotionResult:
    """Validated, structured inference result (never fabricated)."""

    emotion: str
    confidence: float
    margin: float
    probabilities: dict[str, float]
    suggested_mood: str
    model_version: str = MODEL_VERSION_DEFAULT
    analysis_version: str = ANALYSIS_VERSION
    extra: dict[str, Any] = field(default_factory=dict)

    def to_response(self) -> dict[str, Any]:
        return {
            "source": "CAMERA",
            "emotion": self.emotion,
            "confidence": self.confidence,
            "margin": self.margin,
            "probabilities": self.probabilities,
            "suggested_mood": self.suggested_mood,
            "model_version": self.model_version,
            "analysis_version": self.analysis_version,
        }


def _load_interpreter_class() -> Any:
    """Return a TFLite/LiteRT Interpreter class (lightweight runtimes only)."""
    try:
        from ai_edge_litert.interpreter import (
            Interpreter,  # type: ignore[import-not-found]
        )

        return Interpreter
    except ImportError:
        pass
    try:
        from tflite_runtime.interpreter import (
            Interpreter,  # type: ignore[import-not-found]
        )

        return Interpreter
    except ImportError:
        pass
    raise FaceEmotionError(
        "runtime_missing",
        "No TFLite runtime installed (ai-edge-litert or tflite-runtime).",
    )


class FaceEmotionAnalyzer:
    """Reusable, thread-safe facial emotion inference service.

    Instantiate once (see get_face_emotion_analyzer) — never per request.
    """

    def __init__(
        self,
        model_path: str | Path,
        *,
        labels: tuple[str, ...] | list[str] = VIT_FER_7_LABELS,
        model_version: str = MODEL_VERSION_DEFAULT,
        confidence_threshold: float = 0.6,
        margin_threshold: float = 0.10,
        normalization: str = "mean_std_0.5",
        num_threads: int = 2,
    ) -> None:
        self.model_path = Path(model_path)
        self.labels = tuple(labels)
        self.model_version = model_version
        self.confidence_threshold = confidence_threshold
        self.margin_threshold = margin_threshold
        self.normalization = normalization
        self.num_threads = num_threads
        self._lock = threading.Lock()
        self._interpreter: Any = None
        self._input_index = 0
        self._output_index = 0

    # ── Lifecycle ──────────────────────────────────────────────────────
    @property
    def loaded(self) -> bool:
        return self._interpreter is not None

    def load(self) -> FaceEmotionAnalyzer:
        """Load and validate the model. Raises FaceEmotionError if incompatible."""
        if self._interpreter is not None:
            return self
        if len(self.labels) != MODEL_NUM_CLASSES:
            raise FaceEmotionError(
                "label_mismatch",
                f"Expected {MODEL_NUM_CLASSES} emotion labels, got {len(self.labels)}.",
            )
        if not self.model_path.is_file():
            raise FaceEmotionError(
                "model_missing",
                "Emotion model file is not available.",
            )
        Interpreter = _load_interpreter_class()
        try:
            interpreter = Interpreter(
                model_path=str(self.model_path), num_threads=self.num_threads
            )
            interpreter.allocate_tensors()
        except Exception as exc:
            raise FaceEmotionError(
                "model_load_failed",
                f"Emotion model failed to load: {type(exc).__name__}",
            ) from exc

        inputs = interpreter.get_input_details()
        outputs = interpreter.get_output_details()
        if len(inputs) != 1 or len(outputs) != 1:
            raise FaceEmotionError(
                "tensor_mismatch",
                "Emotion model must expose exactly one input and one output tensor.",
            )
        self._validate_tensor(inputs[0], kind="input")
        self._validate_tensor(outputs[0], kind="output")
        self._input_index = inputs[0]["index"]
        self._output_index = outputs[0]["index"]
        self._interpreter = interpreter
        log.info(
            "face_emotion_model_loaded",
            model=str(self.model_path),
            version=self.model_version,
            labels=list(self.labels),
        )
        return self

    @staticmethod
    def _validate_tensor(detail: dict[str, Any], *, kind: str) -> None:
        import numpy as _np  # local import: numpy ships with the runtime deps

        shape = list(detail["shape"])
        dtype = detail["dtype"]
        if kind == "input":
            # NCHW for the ViT. An NHWC model is rejected here rather than
            # silently transposing the wrong way.
            expected = [
                1,
                MODEL_INPUT_CHANNELS,
                MODEL_INPUT_HEIGHT,
                MODEL_INPUT_WIDTH,
            ]
            if shape != expected:
                raise FaceEmotionError(
                    "tensor_mismatch",
                    f"Unexpected model input shape {shape}; expected "
                    f"{expected} (NCHW).",
                )
            if dtype != _np.float32:
                raise FaceEmotionError(
                    "tensor_mismatch",
                    f"Unexpected model input dtype {dtype}; expected float32.",
                )
        else:
            if shape != [1, MODEL_NUM_CLASSES]:
                raise FaceEmotionError(
                    "tensor_mismatch",
                    f"Unexpected model output shape {shape}; "
                    f"expected [1, {MODEL_NUM_CLASSES}].",
                )
            if dtype != _np.float32:
                raise FaceEmotionError(
                    "tensor_mismatch",
                    f"Unexpected model output dtype {dtype}; expected float32.",
                )

    # ── Inference ──────────────────────────────────────────────────────
    def predict(self, image_bytes: bytes) -> FaceEmotionResult:
        """Classify a face-crop image. Raises FaceEmotionError on any failure."""
        if self._interpreter is None:
            raise FaceEmotionError("model_unavailable", "Emotion model is not loaded.")
        pixels = self._preprocess(image_bytes)
        raw = self._invoke(pixels)
        return self._decode(raw)

    def _preprocess(self, image_bytes: bytes) -> Any:
        """Decode -> validate -> resize -> RGB -> normalize -> NCHW tensor."""
        import numpy as _np
        from PIL import Image  # type: ignore[import-not-found]

        try:
            with Image.open(io.BytesIO(image_bytes)) as img:
                img.load()
                if img.width < _MIN_CROP_SIDE_PX or img.height < _MIN_CROP_SIDE_PX:
                    raise FaceEmotionError(
                        "face_too_small",
                        f"Face crop is too small ({img.width}x{img.height}); "
                        f"minimum side is {_MIN_CROP_SIDE_PX}px.",
                    )
                rgb = img.convert("RGB").resize((MODEL_INPUT_WIDTH, MODEL_INPUT_HEIGHT))
                # HWC uint8 -> float32 HWC, so the quality gate still sees
                # 0-255 pixels.
                arr = _np.asarray(rgb, dtype=_np.float32)
        except FaceEmotionError:
            raise
        except Exception as exc:
            raise FaceEmotionError(
                "invalid_image",
                "Image could not be decoded. Use JPEG, PNG, or WebP.",
            ) from exc

        self._check_crop_quality(arr)  # 0-255 scale, before normalization
        if self.normalization == "div255":
            arr = arr / 255.0
        elif self.normalization in ("mean_std_0.5", "mobilenet"):
            # mean/std 0.5 == x/127.5 - 1. "mobilenet" is retained only as a
            # deprecated alias for the same arithmetic so an environment that
            # still carries the old value keeps working; it will not be
            # removed silently.
            if self.normalization == "mobilenet":
                log.warning(
                    "emotion_normalization_deprecated",
                    value="mobilenet",
                    replacement="mean_std_0.5",
                )
            arr = arr / 127.5 - 1.0
        else:
            raise FaceEmotionError(
                "config_error",
                f"Unknown EMOTION_NORMALIZATION={self.normalization!r}; "
                "expected 'mean_std_0.5' or 'div255'.",
            )
        # HWC -> CHW. The ViT consumes NCHW; skipping this is a hard shape
        # error, not a silent quality loss.
        return _np.expand_dims(_np.transpose(arr, (2, 0, 1)), axis=0)

    @staticmethod
    def _check_crop_quality(arr: Any) -> None:
        """Reject flat/extreme exposures instead of fabricating an emotion.

        Runs on 0-255 pixels before normalization.
        """
        import numpy as _np

        luma = _np.asarray(arr, dtype=_np.float64).mean(axis=-1)
        brightness = float(luma.mean())
        contrast = float(luma.std())
        if not (_MIN_BRIGHTNESS <= brightness <= _MAX_BRIGHTNESS):
            raise FaceEmotionError(
                "poor_quality",
                "Face crop exposure is outside the usable range.",
            )
        if contrast < _MIN_CONTRAST:
            raise FaceEmotionError(
                "poor_quality",
                "Face crop has too little contrast to classify.",
            )

    def _invoke(self, batch: Any) -> Any:
        import numpy as _np

        try:
            with self._lock:  # TFLite interpreters are not thread-safe
                self._interpreter.set_tensor(self._input_index, batch)
                self._interpreter.invoke()
                return _np.array(self._interpreter.get_tensor(self._output_index))
        except Exception as exc:
            raise FaceEmotionError(
                "inference_failed", "Emotion inference failed."
            ) from exc

    def _decode(self, raw: Any) -> FaceEmotionResult:
        """Validate output tensor and build the structured result."""
        import math

        import numpy as _np

        if raw is None or _np.asarray(raw).shape != (1, MODEL_NUM_CLASSES):
            raise FaceEmotionError(
                "invalid_output", "Emotion model returned no output."
            )
        scores = _np.asarray(raw[0], dtype=_np.float64)
        if scores.shape != (MODEL_NUM_CLASSES,):
            raise FaceEmotionError(
                "invalid_output", "Emotion model output is malformed."
            )
        if not all(math.isfinite(float(v)) for v in scores):
            raise FaceEmotionError(
                "invalid_output", "Emotion model returned non-finite scores."
            )
        if not all(math.isfinite(float(v)) for v in scores):
            raise FaceEmotionError(
                "invalid_output", "Emotion model returned non-finite scores."
            )
        # Decide between "already probabilities" and "raw logits" by looking
        # at the values, never by requiring a positive sum. The ViT emits
        # logits whose sum is routinely negative (e.g. -1.19 on a clean crop),
        # so an earlier `sum() <= 0 -> invalid` guard rejected perfectly good
        # predictions with a 503.
        if float(scores.min()) >= 0.0 and abs(float(scores.sum()) - 1.0) <= 1e-3:
            probabilities_arr = scores  # already a probability distribution
        else:
            # Logits -> softmax, shifted by the max for numerical stability.
            shifted = _np.exp(scores - scores.max())
            probabilities_arr = shifted / shifted.sum()
        scores = probabilities_arr

        probabilities = {
            label: round(float(scores[i]), 4) for i, label in enumerate(self.labels)
        }
        # Sorted descending so the margin is always top-1 minus the true
        # runner-up, regardless of index order.
        order = _np.argsort(scores)[::-1]
        top_idx = int(order[0])
        runner_up_idx = int(order[1])
        top_confidence = round(float(scores[top_idx]), 4)
        margin = round(float(scores[top_idx] - scores[runner_up_idx]), 4)
        if not 0.0 <= top_confidence <= 1.0:
            raise FaceEmotionError(
                "invalid_output", "Emotion confidence is out of range."
            )
        if not 0.0 <= margin <= 1.0:
            raise FaceEmotionError(
                "invalid_output", "Emotion margin is out of range."
            )

        # Both gates must pass. A high-confidence-but-ambiguous top-1 (the
        # classic ViT failure mode) and a decisive-but-low-confidence top-1
        # both mean "not sure", so neither is forced into a label.
        if (
            top_confidence < self.confidence_threshold
            or margin < self.margin_threshold
        ):
            emotion = "uncertain"  # never force a low-confidence prediction
        else:
            emotion = self.labels[top_idx]
        return FaceEmotionResult(
            emotion=emotion,
            confidence=top_confidence,
            margin=margin,
            probabilities=probabilities,
            suggested_mood=_EMOTION_TO_MOOD.get(emotion, "okay"),
            model_version=self.model_version,
        )


# ── Process-wide singleton (mirrors get_text_analyzer) ──────────────────
_face_analyzer: FaceEmotionAnalyzer | None = None
_init_lock = threading.Lock()


def build_face_emotion_analyzer() -> FaceEmotionAnalyzer:
    """Build from centralized settings (no hard-coded env paths)."""
    from app.config import settings

    labels = tuple(settings.emotion_labels) or VIT_FER_7_LABELS
    return FaceEmotionAnalyzer(
        settings.emotion_model_path,
        labels=labels,
        model_version=settings.emotion_model_version,
        confidence_threshold=settings.emotion_confidence_threshold,
        margin_threshold=settings.emotion_margin_threshold,
        normalization=settings.emotion_normalization,
        num_threads=settings.emotion_threads,
    )


def get_face_emotion_analyzer() -> FaceEmotionAnalyzer:
    global _face_analyzer
    if _face_analyzer is None:
        with _init_lock:
            if _face_analyzer is None:
                analyzer = build_face_emotion_analyzer()
                analyzer.load()  # raises FaceEmotionError; caller maps to 503
                _face_analyzer = analyzer
    return _face_analyzer


def warmup_face_emotion_analyzer() -> bool:
    """Best-effort preload at startup. Never raises (protects existing flows)."""
    try:
        get_face_emotion_analyzer()
        return True
    except Exception:
        log.warning("face_emotion_model_preload_failed", exc_info=True)
        return False
