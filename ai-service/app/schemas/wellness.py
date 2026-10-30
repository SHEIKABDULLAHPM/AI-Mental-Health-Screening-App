"""Schemas for the physical wellness insight endpoint."""

from __future__ import annotations

from pydantic import BaseModel, Field


class InsightPattern(BaseModel):
    """Deterministic pattern computed by the backend pattern engine."""

    id: str = Field(max_length=64)
    severity: str = Field(default="INFO", max_length=16)
    confidence: str = Field(default="LOW", max_length=16)
    summary: str = Field(default="", max_length=600)


class CoverageInput(BaseModel):
    activity_days: int = Field(default=0, ge=0, le=366)
    sleep_days: int = Field(default=0, ge=0, le=366)
    hydration_days: int = Field(default=0, ge=0, le=366)
    mood_checkins: int = Field(default=0, ge=0, le=366)


class GoalInput(BaseModel):
    hydration_target_ml: int = Field(default=0, ge=0, le=10000)
    sleep_target_minutes: int = Field(default=0, ge=0, le=960)


class PhysicalInsightRequest(BaseModel):
    """Aggregated context only — no identifiers, raw readings or free text."""

    window_days: int = Field(default=14, ge=1, le=90)
    coverage: CoverageInput = Field(default_factory=CoverageInput)
    patterns: list[InsightPattern] = Field(default_factory=list, max_length=20)
    existing_recommendations: list[str] = Field(default_factory=list, max_length=20)
    goals: GoalInput = Field(default_factory=GoalInput)


class WellnessRecommendation(BaseModel):
    id: str = Field(max_length=64)
    title: str = Field(max_length=120)
    description: str = Field(max_length=600)
    category: str = Field(default="WELLNESS", max_length=32)
    source: str = Field(default="AI_SERVICE", max_length=32)


class PhysicalInsightResponse(BaseModel):
    recommendations: list[WellnessRecommendation] = Field(default_factory=list)
    note: str | None = None
    # "llm" when wording was generated and validated, "rules" otherwise.
    generated_by: str = Field(default="rules", max_length=16)


class CombinedMentalInput(BaseModel):
    """Deterministic mental profile aggregates - no answers or free text."""

    wellness_score: int = Field(ge=0, le=100)
    stress_level: str = Field(default="MODERATE", max_length=16)
    lifestyle_score: int = Field(default=0, ge=0, le=100)
    sleep_quality: str = Field(default="FAIR", max_length=16)
    primary_focus: str = Field(default="BALANCE", max_length=32)
    safety_flag: bool = False
    mood: str | None = Field(default=None, max_length=32)
    mood_trend: str | None = Field(default=None, max_length=32)


class CombinedSuggestion(BaseModel):
    title: str = Field(max_length=120)
    description: str = Field(max_length=600)
    category: str = Field(default="WELLNESS", max_length=32)


class CombinedPhysicalInput(BaseModel):
    window_days: int = Field(default=14, ge=1, le=90)
    sufficient_data: bool = False
    coverage: CoverageInput = Field(default_factory=CoverageInput)
    pattern_ids: list[str] = Field(default_factory=list, max_length=20)
    suggestions: list[CombinedSuggestion] = Field(default_factory=list, max_length=3)


class CombinedInsightRequest(BaseModel):
    """Anonymised aggregates only - no identifiers, raw readings or free text."""

    mental: CombinedMentalInput
    physical: CombinedPhysicalInput = Field(default_factory=CombinedPhysicalInput)


class CombinedInsightResponse(BaseModel):
    narrative: str = Field(min_length=1, max_length=2000)
    suggestions: list[CombinedSuggestion] = Field(default_factory=list, max_length=3)
    generated_by: str = Field(default="rules", max_length=16)
    note: str | None = None
