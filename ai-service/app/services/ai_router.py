"""Orchestration: routes inbound requests to the correct AI module.

The primary pipeline is the asynchronous screening analysis consumed from
RabbitMQ: deterministic scores -> RAG evidence -> Gemini structured insight.
"""
import asyncio
from typing import Any

from app.config import settings
from app.core.llm.client import LLMClient, build_llm_client
from app.core.prompts import build_screening_prompt
from app.core.rag import QdrantVectorStore
from app.core.recommendation import Recommender, FallbackRecommender
from app.core.risk import HeuristicRiskAssessor, RiskAssessor
from app.errors import AIError, LLMError, RAGSearchError
from app.logging import get_logger
from app.schemas.job import AiInsightResult, ScreeningScoresInput

log = get_logger(__name__)

_INSIGHT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "aiInsight": {"type": "STRING"},
        "evidenceSources": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
    "required": ["aiInsight"],
}


class AIRouter:
    def __init__(self) -> None:
        self.llm: LLMClient = build_llm_client()
        self.risk: RiskAssessor = HeuristicRiskAssessor()
        self.recommender: Recommender = FallbackRecommender()
        self.rag = None
        if settings.rag_enabled:
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

    async def retrieve_evidence(self, query: str, top_k: int | None = None) -> list[str]:
        """Best-effort RAG retrieval; never raises - falls back to no evidence."""
        if self.rag is None:
            return []
        try:
            return self.rag.search(query, top_k=top_k or settings.rag_top_k)
        except RAGSearchError:
            log.warning("rag_search_failed", exc_info=True)
            return []

    async def generate_insight(
        self, scores: ScreeningScoresInput, evidence: list[str]
    ) -> AiInsightResult:
        """Runs the LLM and strictly validates the structured output.

        Transport/5xx errors are retried inside the client; a *valid* JSON
        payload that fails schema validation (e.g. diagnosis-like phrasing) is
        regenerated a bounded number of times before the job is failed - the
        model's phrasing is non-deterministic, so one flaky sentence should
        not permanently fail a user's analysis.
        """
        system, user = build_screening_prompt(scores, evidence)
        validation_attempts = max(1, min(settings.max_llm_attempts, 3))
        raw: dict[str, Any] = {}
        last_error: str | None = None
        for attempt in range(validation_attempts):
            raw = await self.llm.complete_json(
                system, user, _INSIGHT_SCHEMA, max_tokens=settings.llm_max_tokens
            )
            try:
                return AiInsightResult(**raw)
            except LLMError:
                # Transport / malformed-JSON errors already exhausted their own
                # retries inside the client; a retry here would double them.
                raise
            except Exception as exc:  # noqa: BLE001
                last_error = str(exc)
                log.warning("insight_validation_retry", attempt=attempt + 1,
                            error=str(exc), snippet=str(raw.get("aiInsight", ""))[:120])
                if attempt < validation_attempts - 1:
                    await asyncio.sleep(settings.callback_backoff_seconds * (attempt + 1))
        log.error("insight_schema_validation_failed", error=last_error, raw=str(raw)[:500])
        raise LLMError(f"LLM output failed validation: {last_error}")

    async def analyze_job(self, job_scores: dict) -> dict:
        """Full job pipeline: validate scores, retrieve evidence, run LLM."""
        try:
            scores = ScreeningScoresInput(**job_scores)
        except Exception as exc:  # noqa: BLE001
            raise AIError(f"Invalid job scores: {exc}") from exc

        evidence = await self.retrieve_evidence(scores.primaryFocus)
        result = await self.generate_insight(scores, evidence)
        return result.model_dump()


ai_router = AIRouter()
