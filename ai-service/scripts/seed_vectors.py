#!/usr/bin/env python3
"""Seed Qdrant with sample evidence documents for RAG development.

Usage:
    python scripts/seed_vectors.py
"""
import sys

sys.path.insert(0, ".")  # noqa: PGH003

from app.core.rag import QdrantVectorStore  # noqa: E402


SAMPLES = [
    {"id": 1, "source": "crisis-lines", "text": "If you or someone you know is in immediate danger, contact local emergency services or a mental-health crisis line right away."},
    {"id": 2, "source": "self-care", "text": "Grounding techniques such as box breathing can help manage acute anxiety episodes."},
    {"id": 3, "source": "sleep-hygiene", "text": "Consistent sleep schedules improve mood and reduce fatigue for most people."},
]


def main() -> None:
    store = QdrantVectorStore()
    store.upsert(SAMPLES)
    print(f"Seeded {len(SAMPLES)} chunks into '{store._collection}'.")


if __name__ == "__main__":
    sys.exit(main())