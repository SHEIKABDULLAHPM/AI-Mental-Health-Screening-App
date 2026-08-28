from fastapi import APIRouter, Depends

from app.core.ratelimit import rate_limited
from app.core.risk import HeuristicRiskAssessor
from app.schemas.models import RiskRequest

router = APIRouter(dependencies=[Depends(rate_limited)])


@router.post("/assess", summary="Assess clinical risk level")
async def assess(payload: RiskRequest):
    assessor = HeuristicRiskAssessor()
    return await assessor.assess(payload.screening_score, payload.contextual_flags)