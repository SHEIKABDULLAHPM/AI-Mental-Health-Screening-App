"""Unit tests for the Qdrant-backed vector store - especially the explicit
empty-collection path so RAG grounding failures are never silent."""
from unittest.mock import MagicMock

import pytest

from app.core.rag.vector_store import QdrantVectorStore
from app.errors import RAGSearchError


def _store_with_collection(count: int) -> QdrantVectorStore:
    store = QdrantVectorStore.__new__(QdrantVectorStore)  # skip network __init__
    store._collection = "mindease_chunks"
    store._empty_warned = False
    client = MagicMock()
    client.count.return_value.count = count
    store._client = client
    store._embed = lambda texts: [[0.1] * 384]
    return store


def test_empty_collection_returns_no_evidence(caplog):
    store = _store_with_collection(0)

    with caplog.at_level("WARNING"):
        result = store.search("anxiety", top_k=5)

    assert result == []
    assert any("rag_collection_empty" in r.getMessage() for r in caplog.records)


def test_empty_collection_warns_only_once(caplog):
    store = _store_with_collection(0)

    with caplog.at_level("WARNING"):
        store.search("a", top_k=5)
        store.search("b", top_k=5)

    warnings = [r for r in caplog.records if "rag_collection_empty" in r.getMessage()]
    assert len(warnings) == 1


def test_populated_collection_returns_payload_text():
    store = _store_with_collection(3)
    hit = MagicMock()
    hit.payload = {"text": "Evidence chunk", "source": "NIMH"}
    store._client.query_points.return_value.points = [hit]

    assert store.search("stress", top_k=5) == ["Evidence chunk"]


def test_qdrant_failure_raises_rag_search_error():
    store = _store_with_collection(1)
    store._client.query_points.side_effect = RuntimeError("qdrant down")

    with pytest.raises(RAGSearchError):
        store.search("stress", top_k=5)