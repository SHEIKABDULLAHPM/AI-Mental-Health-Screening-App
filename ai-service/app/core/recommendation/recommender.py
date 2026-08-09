"""Recommendation engine combining RAG evidence + user context."""
import abc
from typing import Any


class Recommender(abc.ABC):
    """Produces supportive guidance given a user's context and evidence."""

    @abc.abstractmethod
    def recommend(self, user_context: dict[str, Any], evidence: list[str]) -> dict[str, Any]:
        """Returns {recommendations, referrals, grounding_log}."""
        ...


class FallbackRecommender(Recommender):
    """Safe no-AI fallback; returns crisis-safe guidance without LLM calls."""

    def recommend(self, user_context: dict[str, Any], evidence: list[str]) -> dict[str, Any]:
        return {
            "recommendations": [
                "Speak with someone you trust.",
                "Consider speaking with a licensed professional.",
            ],
            "referrals": [],
            "grounding_used": bool(evidence),
            "source": "fallback",
        }