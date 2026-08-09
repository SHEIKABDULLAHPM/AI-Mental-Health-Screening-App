"""Qdrant-backed vector store for RAG evidence grounding."""
from qdrant_client import QdrantClient, models

from app.config import settings
from app.errors import EmbeddingError, RAGSearchError
from app.logging import get_logger

log = get_logger(__name__)

_EMBEDDING_DIM = 384  # sentence-transformers/all-MiniLM-L6-v2


class QdrantVectorStore:
    def __init__(self) -> None:
        self._client = QdrantClient(url=settings.qdrant_url)
        self._collection = settings.qdrant_collection
        self._ensure_collection()

    def _ensure_collection(self) -> None:
        try:
            if not self._client.collection_exists(self._collection):
                self._client.create_collection(
                    collection_name=self._collection,
                    vectors_config=models.VectorParams(
                        size=_EMBEDDING_DIM,
                        distance=models.Distance.COSINE,
                    ),
                )
                log.info("collection_created", collection=self._collection)
        except Exception as exc:  # noqa: BLE001
            log.error("qdrant_init_failed", error=str(exc))

    def _embed(self, texts: list[str]) -> list[list[float]]:
        try:
            from sentence_transformers import SentenceTransformer
            model = SentenceTransformer(settings.embedding_model)
            return [v.tolist() for v in model.encode(texts)]
        except Exception as exc:  # noqa: BLE001
            raise EmbeddingError(f"embedding failed: {exc}") from exc

    def upsert(self, points: list[dict]) -> None:
        vectors = self._embed([p["text"] for p in points])
        self._client.upsert(
            collection_name=self._collection,
            points=[
                models.PointStruct(
                    id=p["id"],
                    vector=vectors[i],
                    payload={k: v for k, v in p.items() if k not in {"id", "text"}} | {"text": p["text"]},
                )
                for i, p in enumerate(points)
            ],
        )
        log.info("upsert_done", count=len(points))

    def search(self, query: str, *, top_k: int = 5) -> list[str]:
        try:
            vector = self._embed([query])[0]
            hits = self._client.query_points(
                collection_name=self._collection,
                query=vector,
                limit=top_k,
            ).points
            return [h.payload.get("text", "") for h in hits if h.payload]
        except Exception as exc:  # noqa: BLE001
            raise RAGSearchError(f"qdrant search failed: {exc}") from exc