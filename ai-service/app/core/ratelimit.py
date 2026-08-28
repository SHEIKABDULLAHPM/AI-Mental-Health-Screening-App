"""Small fixed-window in-process rate limiter for the unauthenticated endpoints.

The LLM/RAG endpoints are public and unauthenticated (no job is involved), so
they are throttled per client IP to bound abuse and LLM billing exposure.
A single-process fixed window is sufficient here: the AI service is deployed
as one replicon behind a host-published port only in development.
"""
import threading
import time

from fastapi import HTTPException, Request

from app.config import settings


class _Bucket:
    __slots__ = ("count", "window_start")

    def __init__(self) -> None:
        self.window_start = int(time.monotonic())
        self.count = 0


class RateLimiter:
    """Thread-safe fixed-window limiter keyed by an arbitrary client string."""

    def __init__(self, limit_per_minute: int = 120) -> None:
        self._limit = limit_per_minute
        self._lock = threading.Lock()
        self._buckets: dict[str, _Bucket] = {}

    def allow(self, key: str) -> bool:
        now = int(time.monotonic())
        window = 60
        with self._lock:
            bucket = self._buckets.get(key)
            if bucket is None or now - bucket.window_start >= window:
                self._buckets[key] = _Bucket()
                bucket = self._buckets[key]
            bucket.count += 1
            return bucket.count <= self._limit


_limiter = RateLimiter(settings.rate_limit_per_minute)


def per_ip(request: Request) -> str:
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def rate_limited(request: Request) -> None:
    """FastAPI dependency: rejects requests from over-limit client IPs."""
    if not settings.rate_limit_enabled:
        return
    if not _limiter.allow(per_ip(request)):
        raise HTTPException(
            status_code=429,
            detail="Too many requests. Please slow down and try again shortly.",
        )