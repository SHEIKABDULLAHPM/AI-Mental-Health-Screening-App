"""Risk assessment abstraction for crisis/safety scoring."""
import abc
from typing import Any


class RiskAssessor(abc.ABC):
    """Evaluates clinical risk level from screening scores and contextual flags."""

    @abc.abstractmethod
    async def assess(self, scores: dict[str, float], flags: list[str]) -> dict[str, Any]:
        """Returns {level, score, immediate_care_required, reasons}."""


class HeuristicRiskAssessor(RiskAssessor):
    """Threshold-based baseline (PHQ-9/GAD-7 severity bands).

    Replace or augment with a trained model later; keep the interface.
    """

    async def assess(self, scores: dict[str, float], flags: list[str]) -> dict[str, Any]:
        phq = scores.get("phq9", 0.0)
        gad = scores.get("gad7", 0.0)
        max_score = max(phq, gad)
        level = "low"
        if max_score >= 15 or any(f in {"suicide", "self-harm"} for f in flags):
            level = "severe"
        elif max_score >= 10:
            level = "moderate"
        elif max_score >= 5:
            level = "mild"

        return {
            "level": level,
            "score": max_score,
            "immediate_care_required": level == "severe",
            "reasons": ["phq9", "gad7", *flags],
        }