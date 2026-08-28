"""Unit tests for the Gemini JSON extraction helper."""

from app.core.llm.gemini_client import _extract_json_object


def test_parses_plain_json():
    assert _extract_json_object('{"aiInsight": "hello"}') == {"aiInsight": "hello"}


def test_parses_json_in_markdown_fence():
    text = '```json\n{"aiInsight": "hello"}\n```'
    assert _extract_json_object(text) == {"aiInsight": "hello"}


def test_parses_json_with_leading_prose():
    text = 'Here is your result: {"aiInsight": "hello"} thanks'
    assert _extract_json_object(text) == {"aiInsight": "hello"}


def test_parses_nested_json_in_prose():
    text = 'Answer: {"a": {"b": [1, 2]}, "c": 3} ok'
    assert _extract_json_object(text) == {"a": {"b": [1, 2]}, "c": 3}


def test_rejects_non_object_json():
    assert _extract_json_object("[1, 2, 3]") is None
    assert _extract_json_object('"just a string"') is None


def test_rejects_invalid_json():
    assert _extract_json_object("{not json") is None
    assert _extract_json_object("no braces here") is None