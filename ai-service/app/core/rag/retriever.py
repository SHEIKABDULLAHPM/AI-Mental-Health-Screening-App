"""RAG: embedding + vector-store retrieval backed by Qdrant."""
import abc
from typing import Any


class VectorStore(abc.ABC):
    @abc.abstractmethod
    async def upsert(self, points: list[dict[str, Any]]) -> None: ...

    @abc.abstractmethod
    async def search(self, vector: list[float], *, top_k: int = 5) -> list[dict[str, Any]]: ...


class Retriever(abc.ABC):
    @abc.abstractmethod
    async def retrieve(self, query: str, *, top_k: int = 5) -> list[str]:
        """Returns scored evidence chunks relevant to the query."""
        ...