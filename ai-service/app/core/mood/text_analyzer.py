"""Pretrained NLP-based text emotion and sentiment analyzer.

Uses Hugging Face transformers with two pinned models:
- j-hartmann/emotion-english-distilroberta-base   (emotion classification)
- cardiffnlp/twitter-roberta-base-sentiment-latest (sentiment classification)

Both are well-established, openly licensed research models suitable for
wellness-support signals.  They are NOT diagnostic instruments.
"""

from __future__ import annotations

import abc
import threading
from typing import Any

from app.logging import get_logger

log = get_logger(__name__)

# ── Model IDs (pinned) ──────────────────────────────────────────────
EMOTION_MODEL = "j-hartmann/emotion-english-distilroberta-base"
SENTIMENT_MODEL = "cardiffnlp/twitter-roberta-base-sentiment-latest"

EMOTION_LABELS = ["anger", "disgust", "fear", "joy", "neutral", "sadness", "surprise"]
SENTIMENT_LABELS = ["negative", "neutral", "positive"]

# Emotion → simplified mood mapping for downstream consumers
_EMOTION_TO_MOOD: dict[str, str] = {
    "joy": "happy",
    "surprise": "okay",
    "neutral": "calm",
    "sadness": "low",
    "anger": "stressed",
    "fear": "stressed",
    "disgust": "low",
}

# Sentiment → polarity label
_SENTIMENT_POLARITY: dict[str, str] = {
    "positive": "positive",
    "neutral": "neutral",
    "negative": "negative",
}

# Confidence thresholds — below this, return "unknown" instead of a forced label
_EMOTION_CONFIDENCE_THRESHOLD = 0.35
_SENTIMENT_CONFIDENCE_THRESHOLD = 0.30


class TextAnalyzer(abc.ABC):
    """Abstract text mood analyzer."""

    @abc.abstractmethod
    def analyze(self, text: str) -> dict[str, Any]:
        """Analyze text and return structured result."""


class _TransformerAnalyzer(TextAnalyzer):
    """Lazy-loading Hugging Face transformer analyzer.

    Models are loaded once on first use and reused across calls.
    Thread-safe via a lock.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._emotion_pipeline: Any = None
        self._sentiment_pipeline: Any = None

    def _ensure_models(self) -> None:
        if self._emotion_pipeline is not None:
            return
        with self._lock:
            if self._emotion_pipeline is not None:
                return
            try:
                from transformers import pipeline as hf_pipeline  # type: ignore[import-untyped]

                log.info("loading_emotion_model", model=EMOTION_MODEL)
                self._emotion_pipeline = hf_pipeline(
                    "text-classification",
                    model=EMOTION_MODEL,
                    top_k=None,
                    truncation=True,
                )
                log.info("loading_sentiment_model", model=SENTIMENT_MODEL)
                self._sentiment_pipeline = hf_pipeline(
                    "text-classification",
                    model=SENTIMENT_MODEL,
                    top_k=None,
                    truncation=True,
                )
                log.info("mood_models_loaded")
            except Exception:
                log.warning("transformer_model_load_failed", exc_info=True)
                self._emotion_pipeline = None
                self._sentiment_pipeline = None
                raise

    def analyze(self, text: str) -> dict[str, Any]:
        self._ensure_models()

        result: dict[str, Any] = {
            "source": "TEXT",
            "emotion": "unknown",
            "emotion_confidence": 0.0,
            "sentiment": "unknown",
            "sentiment_confidence": 0.0,
            "suggested_mood": "calm",
            "model_version": EMOTION_MODEL,
        }

        if not text or not text.strip():
            return result

        try:
            # Emotion classification
            emo_results = self._emotion_pipeline(text[:2000])
            if emo_results and isinstance(emo_results[0], list):
                emo_scores = {r["label"].lower(): r["score"] for r in emo_results[0]}
            else:
                emo_scores = {r["label"].lower(): r["score"] for r in emo_results}

            top_emotion = max(emo_scores, key=emo_scores.get)  # type: ignore[arg-type]
            top_confidence = emo_scores[top_emotion]

            if top_confidence >= _EMOTION_CONFIDENCE_THRESHOLD:
                result["emotion"] = top_emotion
                result["emotion_confidence"] = round(top_confidence, 4)
                result["suggested_mood"] = _EMOTION_TO_MOOD.get(top_emotion, "calm")
            else:
                # Low confidence — do not force a label
                result["emotion"] = "unknown"
                result["emotion_confidence"] = round(top_confidence, 4)
                result["suggested_mood"] = "calm"

            # Sentiment classification
            sent_results = self._sentiment_pipeline(text[:2000])
            if sent_results and isinstance(sent_results[0], list):
                sent_scores = {r["label"].lower(): r["score"] for r in sent_results[0]}
            else:
                sent_scores = {r["label"].lower(): r["score"] for r in sent_results}

            top_sentiment = max(sent_scores, key=sent_scores.get)  # type: ignore[arg-type]
            sent_confidence = sent_scores[top_sentiment]

            if sent_confidence >= _SENTIMENT_CONFIDENCE_THRESHOLD:
                result["sentiment"] = _SENTIMENT_POLARITY.get(top_sentiment, "neutral")
                result["sentiment_confidence"] = round(sent_confidence, 4)
            else:
                result["sentiment"] = "unknown"
                result["sentiment_confidence"] = round(sent_confidence, 4)

        except Exception:
            log.warning("text_analysis_failed", exc_info=True)
            # Return unknown on failure — manual mood still works
            result["emotion"] = "unknown"
            result["sentiment"] = "unknown"
            result["emotion_confidence"] = 0.0
            result["sentiment_confidence"] = 0.0

        return result


class _FallbackAnalyzer(TextAnalyzer):
    """Rule-based fallback when transformers are unavailable."""

    _POSITIVE = {"happy", "great", "good", "wonderful", "amazing", "love", "grateful",
                 "thankful", "excited", "calm", "peaceful", "relaxed", "content", "hopeful"}
    _NEGATIVE = {"sad", "bad", "terrible", "awful", "horrible", "hate", "angry",
                 "frustrated", "anxious", "worried", "stressed", "lonely", "tired",
                 "overwhelmed", "hopeless", "worthless", "miserable"}

    def analyze(self, text: str) -> dict[str, Any]:
        words = set(text.lower().split())
        pos = len(words & self._POSITIVE)
        neg = len(words & self._NEGATIVE)
        total = pos + neg or 1

        if pos > neg:
            sentiment, emotion, mood = "positive", "joy", "happy"
            confidence = round(pos / total, 4)
        elif neg > pos:
            sentiment, emotion, mood = "negative", "sadness", "low"
            confidence = round(neg / total, 4)
        else:
            sentiment, emotion, mood = "neutral", "neutral", "calm"
            confidence = 0.5

        # Apply same confidence threshold
        if confidence < _EMOTION_CONFIDENCE_THRESHOLD:
            emotion = "unknown"
        if confidence < _SENTIMENT_CONFIDENCE_THRESHOLD:
            sentiment = "unknown"

        return {
            "source": "TEXT",
            "emotion": emotion,
            "emotion_confidence": confidence,
            "sentiment": sentiment,
            "sentiment_confidence": confidence,
            "suggested_mood": mood,
            "model_version": "rule-based-v1",
        }


def build_text_analyzer() -> TextAnalyzer:
    """Factory: prefer transformers, fall back to rules."""
    try:
        analyzer = _TransformerAnalyzer()
        # Try loading to verify availability
        analyzer._ensure_models()
        log.info("text_analyzer_initialized", engine="transformer")
        return analyzer
    except Exception:
        log.warning("transformer_unavailable_fallback_rules")
        return _FallbackAnalyzer()


# Module-level singleton — initialized on first access
_text_analyzer: TextAnalyzer | None = None
_init_lock = threading.Lock()


def get_text_analyzer() -> TextAnalyzer:
    global _text_analyzer
    if _text_analyzer is None:
        with _init_lock:
            if _text_analyzer is None:
                _text_analyzer = build_text_analyzer()
    return _text_analyzer
