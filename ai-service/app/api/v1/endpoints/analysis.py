"""Personalised wellness analysis endpoint.

Serves the app's three analysis buttons (mental, physical, combined) with one
contracted shape. The backend has already gathered the data, computed the
history comparison and applied its own rules; this endpoint returns
personalised narrative, focus areas, recommendations and next actions.
"""

from fastapi import APIRouter, Depends

from app.core.ratelimit import rate_limited
from app.core.wellness.analysis import analyze_with_llm
from app.schemas.analysis import WellnessAnalysisRequest, WellnessAnalysisResponse

router = APIRouter(dependencies=[Depends(rate_limited)])


@router.post(
    "",
    summary="Personalise a mental, physical or combined wellness analysis",
    response_model=WellnessAnalysisResponse,
)
async def analysis(payload: WellnessAnalysisRequest) -> WellnessAnalysisResponse:
    return await analyze_with_llm(payload)
