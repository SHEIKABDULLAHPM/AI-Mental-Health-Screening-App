"""Tests for mood analysis: text analyzer, fusion engine, and endpoints."""

from __future__ import annotations

import pytest

from app.core.mood.fusion import MultimodalFusionEngine
from app.core.mood.text_analyzer import (
    _FallbackAnalyzer,
    _TransformerAnalyzer,
    warmup_text_analyzer,
)


# ── Text Analyzer (Fallback) ──────────────────────────────────────────

class TestFallbackAnalyzer:
    """Test the rule-based fallback analyzer."""

    def setup_method(self):
        self.analyzer = _FallbackAnalyzer()

    def test_positive_text(self):
        result = self.analyzer.analyze("I feel happy and grateful today")
        assert result["emotion"] == "joy"
        assert result["sentiment"] == "positive"
        assert result["source"] == "TEXT"
        assert result["emotion_confidence"] > 0

    def test_negative_text(self):
        result = self.analyzer.analyze("I feel sad and stressed and lonely")
        assert result["emotion"] == "sadness"
        assert result["sentiment"] == "negative"
        assert result["source"] == "TEXT"

    def test_neutral_text(self):
        result = self.analyzer.analyze("The weather is okay")
        assert result["emotion"] in ("neutral", "unknown")
        assert result["sentiment"] in ("neutral", "unknown")
        assert result["source"] == "TEXT"

    def test_empty_text(self):
        result = self.analyzer.analyze("")
        assert result["emotion"] in ("neutral", "unknown")
        assert result["source"] == "TEXT"

    def test_mixed_sentiment(self):
        result = self.analyzer.analyze("happy sad angry")
        assert result["source"] == "TEXT"
        assert 0.0 <= result["emotion_confidence"] <= 1.0

    def test_confidence_range(self):
        result = self.analyzer.analyze("I feel wonderful and amazing and grateful")
        assert 0.0 <= result["emotion_confidence"] <= 1.0
        assert 0.0 <= result["sentiment_confidence"] <= 1.0

    def test_suggested_mood_mapping(self):
        result = self.analyzer.analyze("I feel happy and excited")
        assert result["suggested_mood"] in ("happy", "calm")

    def test_model_version(self):
        result = self.analyzer.analyze("test")
        assert result["model_version"] == "rule-based-v1"


# ── Text Analyzer (lazy/cold-start behaviour) ──────────────────────────

class TestTextAnalyzerColdStart:
    """The request path must never download models or block for minutes.

    Regression: the first /mood/analyze request loaded two ~500 MB
    transformers on demand and took >4 minutes, far past the backend's 30 s
    timeout, so the user's reflection text was silently dropped.
    """

    def test_request_path_never_downloads(self, monkeypatch):
        analyzer = _TransformerAnalyzer()
        calls = []

        def _boom(*args, **kwargs):
            calls.append(kwargs)
            raise AssertionError("request path attempted a model download")

        # Fail any load that would reach the network.
        monkeypatch.setattr(
            analyzer,
            "_ensure_models",
            lambda **kwargs: _boom(**kwargs),
        )
        result = analyzer.analyze("I feel happy and grateful today")
        assert result["source"] == "TEXT"
        # local_files_only must be requested on the request path.
        assert calls and calls[0].get("allow_download") is False

    def test_missing_models_degrade_to_rule_based(self, monkeypatch):
        analyzer = _TransformerAnalyzer()

        def _fail(**_kwargs):
            raise OSError("model cache missing")

        monkeypatch.setattr(analyzer, "_ensure_models", _fail)
        result = analyzer.analyze("I feel sad and stressed and lonely")
        assert result["model_version"] == "rule-based-v1"
        assert result["sentiment"] == "negative"

    def test_startup_warmup_allows_download(self):
        # Warm-up is the only place a download is acceptable.
        analyzer = _TransformerAnalyzer()
        seen = {}

        def _record(**kwargs):
            seen.update(kwargs)
            raise RuntimeError("stop here, we only inspect the kwargs")

        analyzer._ensure_models = _record  # type: ignore[method-assign]
        with pytest.raises(RuntimeError):
            analyzer._ensure_models(allow_download=True)
        assert seen.get("allow_download") is True

    def test_warmup_returns_engine_name(self):
        engine = warmup_text_analyzer()
        assert engine in ("transformer", "rule-based")


# ── Fusion Engine ─────────────────────────────────────────────────────

class TestMultimodalFusionEngine:
    """Test the deterministic fusion engine."""

    def setup_method(self):
        self.engine = MultimodalFusionEngine()

    def test_manual_only(self):
        result = self.engine.fuse(manual_mood="happy")
        assert result["fused_mood"] == "happy"
        assert result["sources_used"] == ["MANUAL"]
        assert result["manual_mood"] == "happy"
        assert result["confidence"] > 0

    def test_manual_with_text(self):
        text = {
            "emotion": "joy",
            "emotion_confidence": 0.9,
            "sentiment": "positive",
            "sentiment_confidence": 0.85,
        }
        result = self.engine.fuse(
            manual_mood="happy",
            manual_emotion="Grateful",
            text_analysis=text,
        )
        assert "MANUAL" in result["sources_used"]
        assert "TEXT" in result["sources_used"]
        assert result["fused_mood"] == "happy"
        assert result["confidence"] > 0

    def test_manual_with_camera(self):
        camera = {
            "emotion": "happy",
            "confidence": 0.8,
            "valence": 0.7,
            "suggested_mood": "happy",
        }
        result = self.engine.fuse(
            manual_mood="happy",
            camera_analysis=camera,
        )
        assert "MANUAL" in result["sources_used"]
        assert "CAMERA" in result["sources_used"]
        assert result["fused_mood"] == "happy"

    def test_all_three_sources(self):
        text = {
            "emotion": "joy",
            "emotion_confidence": 0.9,
            "sentiment": "positive",
        }
        camera = {
            "emotion": "happy",
            "confidence": 0.8,
            "valence": 0.6,
        }
        result = self.engine.fuse(
            manual_mood="happy",
            manual_emotion="Grateful",
            text_analysis=text,
            camera_analysis=camera,
        )
        assert set(result["sources_used"]) == {"MANUAL", "TEXT", "CAMERA"}
        assert result["confidence"] > 0.5

    def test_no_sources_returns_neutral(self):
        result = self.engine.fuse()
        assert result["fused_mood"] == "okay"
        assert result["fused_emotion"] == "unknown"
        assert result["confidence"] == 0.0
        assert result["needs_confirmation"] is True

    def test_unknown_text_emotion_excluded(self):
        text = {
            "emotion": "unknown",
            "emotion_confidence": 0.2,
        }
        result = self.engine.fuse(
            manual_mood="happy",
            text_analysis=text,
        )
        assert "TEXT" not in result["sources_used"]
        assert result["sources_used"] == ["MANUAL"]

    def test_low_confidence_camera_excluded(self):
        camera = {
            "emotion": "neutral",
            "confidence": 0.1,
        }
        result = self.engine.fuse(
            manual_mood="happy",
            camera_analysis=camera,
        )
        assert "CAMERA" not in result["sources_used"]

    def test_needs_confirmation_on_disagreement(self):
        # Manual says stressed (valence -0.8), AI suggests happy
        text = {
            "emotion": "joy",
            "emotion_confidence": 0.9,
            "sentiment": "positive",
        }
        result = self.engine.fuse(
            manual_mood="stressed",
            text_analysis=text,
        )
        # When manual mood and AI significantly differ, needs_confirmation = True
        assert result["needs_confirmation"] is True

    def test_confidence_always_bounded(self):
        text = {
            "emotion": "joy",
            "emotion_confidence": 1.0,
            "sentiment": "positive",
            "sentiment_confidence": 1.0,
        }
        camera = {
            "emotion": "happy",
            "confidence": 1.0,
            "valence": 1.0,
        }
        result = self.engine.fuse(
            manual_mood="happy",
            text_analysis=text,
            camera_analysis=camera,
        )
        assert 0.0 <= result["confidence"] <= 1.0

    def test_fused_emotion_from_text(self):
        text = {
            "emotion": "anger",
            "emotion_confidence": 0.9,
            "sentiment": "negative",
        }
        result = self.engine.fuse(
            manual_mood="stressed",
            text_analysis=text,
        )
        assert result["fused_emotion"] == "anger"

    def test_fused_emotion_from_camera_when_no_text(self):
        camera = {
            "emotion": "surprise",
            "confidence": 0.8,
            "valence": 0.3,
        }
        result = self.engine.fuse(
            manual_mood="okay",
            camera_analysis=camera,
        )
        assert result["fused_emotion"] == "surprise"

    def test_manual_emotion_fallback(self):
        result = self.engine.fuse(
            manual_mood="happy",
            manual_emotion="Grateful",
        )
        assert result["fused_emotion"] == "Grateful"

    def test_camera_valence_used_when_available(self):
        camera = {
            "emotion": "neutral",
            "confidence": 0.8,
            "valence": 0.5,
        }
        result = self.engine.fuse(
            manual_mood="happy",
            camera_analysis=camera,
        )
        assert result["confidence"] > 0

    def test_camera_suggested_mood_fallback_when_no_valence(self):
        camera = {
            "emotion": "sad",
            "confidence": 0.8,
            "valence": 0.0,
            "suggested_mood": "low",
        }
        result = self.engine.fuse(
            manual_mood="okay",
            camera_analysis=camera,
        )
        assert result["sources_used"] == ["MANUAL", "CAMERA"]

    # ── Manual mood authority (regression) ──────────────────────────────

    def test_manual_mood_is_never_overridden_by_camera(self):
        # Regression: manual "calm" (valence +0.3) blended 50/50 with a
        # confident camera "sad" (valence -1.0) previously resolved to "okay",
        # silently replacing what the user actually reported.
        camera = {
            "emotion": "sad",
            "confidence": 0.8,
            "valence": -1.0,
            "suggested_mood": "stressed",
        }
        result = self.engine.fuse(
            manual_mood="calm",
            camera_analysis=camera,
        )
        assert result["fused_mood"] == "calm"
        assert result["manual_mood"] == "calm"

    def test_manual_mood_is_never_overridden_by_text(self):
        text = {
            "emotion": "grief",
            "emotion_confidence": 0.95,
            "sentiment": "negative",
        }
        result = self.engine.fuse(
            manual_mood="very_happy",
            text_analysis=text,
        )
        assert result["fused_mood"] == "very_happy"

    def test_camera_text_disagreement_asks_for_confirmation(self):
        # Manual "calm" vs a confident camera "sad": the mood of record stays
        # "calm", but the gap must still be surfaced to the user.
        camera = {
            "emotion": "sad",
            "confidence": 0.8,
            "valence": -1.0,
            "suggested_mood": "stressed",
        }
        result = self.engine.fuse(
            manual_mood="calm",
            camera_analysis=camera,
        )
        assert result["fused_mood"] == "calm"
        assert result["needs_confirmation"] is True

    def test_ai_suggested_mood_preserves_blend(self):
        # The AI read must remain visible instead of being discarded when it
        # differs from the manual selection. Manual "calm" (0.3) blended with
        # a confident camera "sad" (-1.0) lands at -0.133, i.e. "okay".
        camera = {
            "emotion": "sad",
            "confidence": 0.8,
            "valence": -1.0,
            "suggested_mood": "stressed",
        }
        result = self.engine.fuse(
            manual_mood="calm",
            camera_analysis=camera,
        )
        assert result["fused_mood"] == "calm"
        assert result["ai_suggested_mood"] == "okay"
        assert result["ai_suggested_mood"] != result["fused_mood"]
        assert result["blended_valence"] == pytest.approx(-0.1333, abs=1e-3)

    def test_agreement_reports_no_confirmation(self):
        camera = {
            "emotion": "happy",
            "confidence": 0.8,
            "valence": 0.7,
        }
        result = self.engine.fuse(
            manual_mood="happy",
            camera_analysis=camera,
        )
        assert result["fused_mood"] == "happy"
        assert result["ai_suggested_mood"] == "happy"
        assert result["needs_confirmation"] is False

    def test_ai_only_blend_used_when_no_manual_mood(self):
        # Without a manual selection the AI read becomes the mood of record.
        camera = {
            "emotion": "sad",
            "confidence": 0.8,
            "valence": -0.8,
            "suggested_mood": "stressed",
        }
        result = self.engine.fuse(camera_analysis=camera)
        assert result["fused_mood"] == "stressed"
        assert result["ai_suggested_mood"] == "stressed"

    def test_manual_mood_without_ai_sources_needs_no_confirmation(self):
        # Manual-only check-ins must not nag the user to confirm themselves.
        result = self.engine.fuse(manual_mood="low")
        assert result["fused_mood"] == "low"
        assert result["sources_used"] == ["MANUAL"]
        assert result["needs_confirmation"] is False


# ── Schema Validation ─────────────────────────────────────────────────

class TestSchemas:
    """Test Pydantic schema validation."""

    def test_text_request_valid(self):
        from app.schemas.mood import TextAnalysisRequest
        req = TextAnalysisRequest(text="I feel great")
        assert req.text == "I feel great"

    def test_text_request_rejects_empty(self):
        from app.schemas.mood import TextAnalysisRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            TextAnalysisRequest(text="")

    def test_camera_request_defaults(self):
        from app.schemas.mood import CameraObservationRequest
        req = CameraObservationRequest(dominant_emotion="happy")
        assert req.face_detected is True
        assert req.face_count == 1
        assert req.frames_analyzed == 1

    def test_camera_request_valence_bounds(self):
        from app.schemas.mood import CameraObservationRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            CameraObservationRequest(
                dominant_emotion="happy",
                valence=1.5,
            )

    def test_mood_analysis_request_requires_manual_mood(self):
        from app.schemas.mood import MoodAnalysisRequest
        from pydantic import ValidationError
        with pytest.raises(ValidationError):
            MoodAnalysisRequest(manual_mood="")

    def test_mood_analysis_response_fields(self):
        from app.schemas.mood import MoodAnalysisResponse
        resp = MoodAnalysisResponse(
            fused_mood="happy",
            fused_emotion="joy",
            confidence=0.8,
            sources_used=["MANUAL"],
            manual_mood="happy",
            text_analysis=None,
            camera_analysis=None,
            needs_confirmation=False,
        )
        assert resp.fused_mood == "happy"
        assert resp.model_version == "multimodal-fusion-v1"
