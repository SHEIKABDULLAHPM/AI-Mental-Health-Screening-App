"""Wellbeing insight endpoints.

* ``/physical-insights`` receives already-aggregated, already-validated
  patterns from the Spring Boot pattern engine and returns supportive
  suggestions. Wording may be LLM-enhanced; the patterns themselves never are.
* ``/combined-insight`` connects the deterministic mental profile with those
  physical aggregates. No raw readings, identifiers or free text are accepted
  by design.
"""

from fastapi import APIRouter, Depends

from app.core.ratelimit import rate_limited
from app.core.wellness.combined_insight import generate_insight
from app.core.wellness.physical_insights import recommend_with_llm
from app.schemas.wellness import (
    CombinedInsightRequest,
    CombinedInsightResponse,
    PhysicalInsightRequest,
    PhysicalInsightResponse,
)

router = APIRouter(dependencies=[Depends(rate_limited)])


@router.post(
    "/physical-insights",
    summary="Generate supportive recommendations from physical patterns",
    response_model=PhysicalInsightResponse,
)
async def physical_insights(payload: PhysicalInsightRequest) -> PhysicalInsightResponse:
    return await recommend_with_llm(payload)


@router.post(
    "/combined-insight",
    summary="Combine the mental profile with physical aggregates",
    response_model=CombinedInsightResponse,
)
async def combined_insight(payload: CombinedInsightRequest) -> CombinedInsightResponse:
    return await generate_insight(payload)
