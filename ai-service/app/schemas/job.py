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
    "you have anxiety",
    "you have ptsd",
    "you have bipolar",
    "you have schizophrenia",
    "you have depressive disorder",
    "you have generalized anxiety disorder",
    "you have clinical depression",
    "you are depressed",
    "you are clinically",
    "depressive disorder",
    "generalized anxiety disorder",
    "clinical depression",
    "diagnosis:",
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
    """Minimal, anonymized deterministic scores sent to the LLM (no raw answers).

    Mood context fields are all optional so jobs created before the Mood
    Check-In onboarding integration keep validating. When present they carry
    only structured, server-derived signals: the self-reported mood stays the
    primary signal, trend/history are deterministic derivations.
    """

    phq9: int = Field(ge=0, le=27)
    gad7: int = Field(ge=0, le=21)
    pss10: int = Field(ge=0, le=40)
    who5: int = Field(ge=0, le=25)
    wellnessScore: int = Field(ge=0, le=100)
    stressLevel: str
    lifestyleScore: int = Field(ge=0, le=100)
    sleepQuality: str
    primaryFocus: str
    onboardingMood: str | None = None
    onboardingMoodScore: int | None = Field(default=None, ge=1, le=6)
    onboardingMoodEmotion: str | None = None
    onboardingMoodIntensity: int | None = Field(default=None, ge=1, le=10)
    moodTrendDirection: str | None = None
    moodTrendDescription: str | None = None
    moodHistoryCount: int | None = Field(default=None, ge=0)
    # Optional camera supporting signal, extracted server-side from the
    # linked mood entry's CAMERA AI observation (never raw frames).
    cameraEmotion: str | None = None
    cameraConfidence: float | None = Field(default=None, ge=0.0, le=1.0)
    cameraModelVersion: str | None = None
    # Deterministic verdict computed server-side: agree|close|differs|noSignal.
    signalAgreement: str | None = None

    @property
    def who_percent(self) -> int:
        return min(self.who5 * 4, 100)

    @property
    def has_mood_context(self) -> bool:
        return bool(self.onboardingMood and self.onboardingMood.strip())
