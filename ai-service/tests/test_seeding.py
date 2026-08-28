"""Unit tests for the knowledge-base seeding chunker."""

from scripts.seed_vectors import _chunk, _sentence_boundary, _source_label


def test_chunk_single_short_text():
    chunks = _chunk("Sleep well and take breaks.")
    assert chunks == ["Sleep well and take breaks."]


def test_chunk_splits_long_text_into_overlapping_windows():
    text = "word " * 400
    chunks = _chunk(text)
    assert len(chunks) > 1
    assert all(len(c) <= 900 for c in chunks)


def test_chunk_prefers_sentence_boundaries():
    text = ("Short sentence here is complete. " * 30)
    chunks = _chunk(text, size=200)
    assert len(chunks) > 2
    assert all(c.endswith(".") for c in chunks)


def test_sentence_boundary_found():
    text = "First sentence ends. Then another sentence follows here."
    boundary = _sentence_boundary(text, 0, len(text))
    assert boundary is not None
    assert text[boundary - 1] == "."


def test_source_label_derived_from_folder_and_stem():
    from pathlib import Path

    label = _source_label(Path("/kb/nimh/Im-So-Stressed-Out.pdf"))
    assert label == "NIMH-IM-SO-STRESSED-OUT"