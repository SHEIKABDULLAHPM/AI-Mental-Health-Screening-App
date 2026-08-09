"""Emotion detection abstraction and neutral baseline implementation."""
import abc
from typing import Any


class EmotionEngine(abc.ABC):
    """Detects emotion, sentiment and intensity from free text."""

    @abc.abstractmethod
    async def analyze(self, text: str) -> dict[str, Any]:
        """Returns {emotion, sentiment, intensity, confidence, flags}."""


class RuleBasedEmotionEngine(EmotionEngine):
    """Offline baseline: keyword + intensity heuristics.

    Intended as a fallback / smoke-test implementation until an ML/LLM
    recommenderdefinition is deployed.
    """

    async def analyze(self, text: str) -> dict[str, Any]:
        flags = []
        for signal in ["suicide", "self-harm", "hopeless", "worthless"]:
            if signal in text.lower():
                flags.append(signal)
        return {
            "emotion": "mixed",
            "sentiment": "neutral",
            "intensity": 0.0,
            "confidence": 0.0,
            "flags": flags,
        }