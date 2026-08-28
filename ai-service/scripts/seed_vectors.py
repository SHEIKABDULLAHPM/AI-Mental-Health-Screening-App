#!/usr/bin/env python3
"""Seed Qdrant with the curated trusted knowledge base (NICE/NIMH/WHO PDFs).

Usage:
    python scripts/seed_vectors.py [--kb-dir ../knowledge-base] [--dry-run]

Extracts text from every PDF under the knowledge-base directory, splits it
into overlapping chunks, embeds them and upserts into the Qdrant collection
configured via QDRANT_URL / QDRANT_COLLECTION. Idempotent: upserting an
existing point id overwrites it, so re-running is safe.

If no parseable PDFs are found a small in-memory starter set is seeded so the
development RAG pipeline is never silently empty.
"""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.rag import QdrantVectorStore

CHUNK_SIZE = 900
CHUNK_OVERLAP = 120

FALLBACK_SAMPLES = [
    {"id": 1, "source": "crisis-lines", "text": "If you or someone you know is in immediate danger, contact local emergency services or a mental-health crisis line right away."},
    {"id": 2, "source": "self-care", "text": "Grounding techniques such as box breathing can help manage acute anxiety episodes."},
    {"id": 3, "source": "sleep-hygiene", "text": "Consistent sleep schedules improve mood and reduce fatigue for most people."},
]


def _source_label(pdf_path: Path) -> str:
    org = pdf_path.parent.name.upper()
    stem = re.sub(r"[^A-Za-z0-9]+", "-", pdf_path.stem).strip("-").upper()
    return f"{org}-{stem}"


def _chunk(text: str, size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []
    chunks: list[str] = []
    start = 0
    length = len(text)
    while start < length:
        end = min(start + size, length)
        # prefer a sentence boundary near the end of the window
        boundary = _sentence_boundary(text, start, end)
        if boundary is not None:
            end = boundary
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end >= length:
            break
        start = max(end - overlap, start + 1)
        if start >= length:
            break
    return chunks


def _sentence_boundary(text: str, start: int, end: int) -> int | None:
    if end - start < 40:
        return end
    lower = max(start, end - 120)
    idx = text.rfind(". ", start, end - 1)
    if idx >= lower:
        return idx + 1
    nl = text.rfind("\n", start, end)
    if nl >= lower:
        return nl + 1
    return None


def _extract_pdf(pdf_path: Path) -> str:
    from pypdf import PdfReader

    reader = PdfReader(str(pdf_path))
    pages = [page.extract_text() or "" for page in reader.pages]
    return "\n\n".join(pages)


def _load_points(kb_dir: Path) -> tuple[list[dict], list[str]]:
    points: list[dict] = []
    errors: list[str] = []
    next_id = 1
    if not kb_dir.is_dir():
        return points, [f"knowledge-base directory not found: {kb_dir}"]
    for pdf_path in sorted(kb_dir.rglob("*.pdf")):
        try:
            text = _extract_pdf(pdf_path)
            chunks = _chunk(text)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{pdf_path.name}: {exc}")
            continue
        if not chunks:
            errors.append(f"{pdf_path.name}: no extractable text")
            continue
        source = _source_label(pdf_path)
        for chunk in chunks:
            points.append({"id": next_id, "source": source, "text": chunk})
            next_id += 1
        print(f"  {pdf_path.name}: {len(chunks)} chunks", flush=True)
    return points, errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kb-dir", type=Path,
                        default=Path(__file__).resolve().parent.parent / "knowledge-base")
    parser.add_argument("--dry-run", action="store_true",
                        help="parse and chunk only; do not write to Qdrant")
    args = parser.parse_args()

    points, errors = _load_points(args.kb_dir)
    for error in errors:
        print(f"SKIPPED {error}", file=sys.stderr, flush=True)
    if not points:
        print("WARNING: no parseable knowledge-base PDFs; using starter samples.",
              file=sys.stderr, flush=True)
        points = [dict(p) for p in FALLBACK_SAMPLES]

    if args.dry_run:
        print(f"DRY RUN: would seed {len(points)} chunks.", flush=True)
        return

    store = QdrantVectorStore()
    store.upsert(points)
    total = len(points)
    print(f"Seeded {total} chunks into '{store._collection}' from {len(points)} points.", flush=True)


if __name__ == "__main__":
    sys.exit(main())