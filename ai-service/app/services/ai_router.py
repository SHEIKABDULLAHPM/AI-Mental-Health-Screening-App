"""Orchestration: routes inbound requests to the correct AI module.

This is the seam where screening analysis is composed:
    risk + emotion + RAG evidence -> recommendation.
"""
from app.core.emotion import EmotionEngine, RuleBasedEmotionEngine
from app.core.rag import QdrantVectorStore
from app.core.recommendation import Recommender, FallbackRecommender
from app.core.risk import HeuristicRiskAssessor, RiskAssessor
from app.logging import get_logger

log = get_logger(__name__)


class AIRouter:
    def __init__(self) -> None:
        self.emotion: EmotionEngine = RuleBasedEmotionEngine()
        self.risk: RiskAssessor = HeuristicRiskAssessor()
        self.recommender: Recommender = FallbackRecommender()
        try:
            self.rag = QdrantVectorStore()
        except Exception:  # noqa: BLE001
            log.warning("rag_unavailable_fallback", exc_info=True)
            self.rag = None

    async def analyze_screening(self, payload: dict) -> dict:
        scores = payload.get("scores", {})
        flags = payload.get("contextual_flags", [])
        risk = await self.risk.assess(scores, flags)
        return {
            "risk": risk,
            "emotion_summary": None,
            "recommendations": None,
            "status": "queued-for-llm",
        }


ai_router = AIRouter()