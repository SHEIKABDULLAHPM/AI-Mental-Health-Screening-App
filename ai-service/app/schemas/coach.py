"""Request/response schemas for coach safety and wellness endpoints."""

from __future__ import annotations

from pydantic import BaseModel, Field


class SafetyClassificationRequest(BaseModel):
    """Classify user message for safety concerns."""

    message: str = Field(min_length=1, max_length=5000, description="User message to classify")


class SafetyClassificationResponse(BaseModel):
    """Safety classification result."""

    state: str = Field(description="NORMAL, CONCERNING, HIGH_RISK, or IMMEDIATE_DANGER")
    confidence: float = Field(ge=0.0, le=1.0)
    keywords_matched: list[str] = Field(default_factory=list)


class WellnessRAGRequest(BaseModel):
    """Retrieve wellness knowledge relevant to a user query."""

    query: str = Field(min_length=1, max_length=2000)
    top_k: int = Field(default=3, ge=1, le=10)


class WellnessRAGResponse(BaseModel):
    """Wellness knowledge retrieval result."""

    query: str
    chunks: list[str]
    sources: list[str] = Field(default_factory=list)
    relevance_threshold_met: bool = True
