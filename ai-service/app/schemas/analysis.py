"""Schemas for the personalised wellness analysis endpoint.

The backend owns all data access and every measurement. This service only
receives already-aggregated numbers the user can see in the app, plus the
deterministic comparison it computed against the previous analysis. It never
receives identifiers, journal text, screening answers or raw wearable samples,
and ``extra="forbid"`` stops a client smuggling any of them in.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.wellness import WellnessRecommendation

#: The three analysis buttons exposed by the app.
AnalysisType = Literal["MENTAL", "PHYSICAL", "COMBINED"]


class AnalysisMetric(BaseModel):
    """One aggregate the user already sees, e.g. steps average or wellness score."""

    model_config = ConfigDict(extra="forbid")

    key: str = Field(min_length=1, max_length=48)
    label: str = Field(min_length=1, max_length=64)
    value: float
    unit: str = Field(default="", max_length=16)


class ComparisonInput(BaseModel):
    """Deterministic history comparison produced by the backend."""

    model_config = ConfigDict(extra="forbid")

    has_previous: bool = False
    days_since_previous: int | None = Field(default=None, ge=0, le=3650)
    #: IMPROVED, DECLINED, UNCHANGED or FIRST_ANALYSIS.
    overall: str = Field(default="FIRST_ANALYSIS", max_length=24)
    improved: list[str] = Field(default_factory=list, max_length=12)
    declined: list[str] = Field(default_factory=list, max_length=12)
    unchanged: list[str] = Field(default_factory=list, max_length=12)


class WellnessAnalysisRequest(BaseModel):
    """Aggregated context only — no identifiers, raw readings or free text."""

    model_config = ConfigDict(extra="forbid")

    type: AnalysisType
    window_days: int = Field(default=14, ge=1, le=90)
    metrics: list[AnalysisMetric] = Field(default_factory=list, max_length=24)
    patterns: list[str] = Field(default_factory=list, max_length=12)
    comparison: ComparisonInput = Field(default_factory=ComparisonInput)
    existing_recommendations: list[str] = Field(default_factory=list, max_length=12)


class WellnessAnalysisResponse(BaseModel):
    narrative: str = Field(min_length=1, max_length=1200)
    recommendations: list[WellnessRecommendation] = Field(default_factory=list, max_length=4)
    focus_areas: list[str] = Field(default_factory=list, max_length=6)
    next_actions: list[str] = Field(default_factory=list, max_length=6)
    #: "llm" only when wording was generated and validated; "rules" otherwise.
    generated_by: str = Field(default="rules", max_length=16)
    note: str | None = None
