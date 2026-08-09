from pydantic import BaseModel, Field


class ScreeningRequest(BaseModel):
    user_id: str
    questionnaire_type: str
    answers: dict[str, int] = Field(description="question_id -> score")


class EmotionRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20000)
    language: str = "auto"


class RiskRequest(BaseModel):
    screening_score: dict[str, float]
    contextual_flags: list[str] = Field(default_factory=list)


class RAGQueryRequest(BaseModel):
    query: str = Field(min_length=1)


class RecommendationRequest(BaseModel):
    user_context: dict[str, str | float]
    evidence_chunks: list[str] = Field(default_factory=list)