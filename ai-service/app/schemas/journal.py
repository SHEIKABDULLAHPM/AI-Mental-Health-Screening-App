"""Request/response schemas for journal analysis endpoints."""

from __future__ import annotations

from pydantic import BaseModel, Field


class JournalAnalysisRequest(BaseModel):
    """Analyze journal text for emotion, sentiment, themes, and reflection."""

    text: str = Field(min_length=1, max_length=5000, description="Journal entry text to analyze")


class JournalAnalysisResponse(BaseModel):
    """Structured journal analysis result."""

    status: str = "COMPLETED"
    emotion: str
    emotionConfidence: float = Field(ge=0.0, le=1.0)
    sentiment: str
    sentimentConfidence: float = Field(ge=0.0, le=1.0)
    emotionalThemes: str | None = None
    summary: str | None = None
    reflectionPrompt: str | None = None
    analysisVersion: str = "journal-emotion-v1"
