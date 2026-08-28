from pydantic import BaseModel, ConfigDict, Field, field_validator

PRIMARY_FOCUS_VALUES = {
    "STRESS_MANAGEMENT",
    "SLEEP",
    "MOOD_SUPPORT",
    "WELLBEING",
    "BALANCE",
}

# Phrasing that would present the output as a diagnosis rather than guidance.
_DIAGNOSIS_TERMS = (
    "diagnosed with",
    "suffering from",
    "a diagnosis of",
    "as a patient",
    "patients with",
    "you have depression",
    "you have anxiety disorder",
    "you have ptsd",
    "you have bipolar",
    "you have schizophrenia",
    "you are depressed",
    "you are clinically",
)


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class AiInsightResult(_Strict):
    """Strictly validated structured output produced by the LLM for a job."""

    aiInsight: str = Field(
        min_length=20,
        max_length=4000,
        description="Empathetic, actionable wellness insight. Guidance, not diagnosis.",
    )
    evidenceSources: list[str] = Field(
        default_factory=list,
        max_length=8,
        description="Trusted knowledge-base references that grounded the insight.",
    )

    @field_validator("aiInsight")
    @classmethod
    def _insight_is_actionable(cls, value: str) -> str:
        value = value.strip()
        lowered = value.lower()
        if lowered.startswith("diagnos") or any(
            term in lowered for term in _DIAGNOSIS_TERMS
        ):
            raise ValueError("insight must not present itself as a diagnosis")
        return value

    @field_validator("evidenceSources")
    @classmethod
    def _sources_are_strings(cls, value: list) -> list:
        if any(not isinstance(item, str) or not item.strip() for item in value):
            raise ValueError("evidenceSources must be non-empty strings")
        return value


class ScreeningScoresInput(_Strict):
    """Minimal, anonymized deterministic scores sent to the LLM (no raw answers)."""

    phq9: int = Field(ge=0, le=27)
    gad7: int = Field(ge=0, le=21)
    pss10: int = Field(ge=0, le=40)
    who5: int = Field(ge=0, le=25)
    wellnessScore: int = Field(ge=0, le=100)
    stressLevel: str
    lifestyleScore: int = Field(ge=0, le=100)
    sleepQuality: str
    primaryFocus: str

    @property
    def who_percent(self) -> int:
        return min(self.who5 * 4, 100)
