from fastapi import APIRouter, HTTPException

from app.core.rag import QdrantVectorStore
from app.schemas.models import RAGQueryRequest

router = APIRouter()
_store = None


def _get_store() -> QdrantVectorStore:
    global _store
    if _store is None:
        _store = QdrantVectorStore()  # may raise if Qdrant is down
    return _store


@router.post("/retrieve", summary="Retrieve evidence chunks by query")
async def retrieve(payload: RAGQueryRequest):
    try:
        chunks = _get_store().search(payload.query, top_k=5)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return {"query": payload.query, "chunks": chunks}