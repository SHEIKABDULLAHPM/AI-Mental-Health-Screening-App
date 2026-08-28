"""Unit tests for the per-IP fixed-window rate limiter guarding the public
unauthenticated LLM/RAG endpoints."""

from app.core import ratelimit
from app.core.ratelimit import RateLimiter


def test_burst_over_limit_is_rejected():
    limiter = RateLimiter(limit_per_minute=2)

    assert limiter.allow("client-a") is True
    assert limiter.allow("client-a") is True
    assert limiter.allow("client-a") is False


def test_clients_are_isolated():
    limiter = RateLimiter(limit_per_minute=1)

    limiter.allow("client-a")
    assert limiter.allow("client-b") is True


def test_window_resets_after_minute(monkeypatch):
    now = {"value": 1000}
    monkeypatch.setattr(ratelimit.time, "monotonic", lambda: now["value"])
    limiter = RateLimiter(limit_per_minute=1)

    assert limiter.allow("client-a") is True
    now["value"] += 61
    assert limiter.allow("client-a") is True