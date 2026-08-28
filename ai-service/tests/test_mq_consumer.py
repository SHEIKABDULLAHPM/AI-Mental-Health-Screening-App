"""Unit tests for the RabbitMQ consumer callback logic.

The consumer is what turns a queued message into a completed job; these tests
verify the backend claim/complete/fail contract and that a transient backend
outage leads to a bounded requeue instead of losing the job silently.
"""
import asyncio
import json

import httpx
import pytest

from app.config import settings
from app.services import mq_consumer
from app.services.mq_consumer import ACK, REQUEUE


def _job_payload(job_id: str = "job-1") -> bytes:
    return json.dumps({"jobId": job_id}).encode()


class _FakeChannel:
    def __init__(self) -> None:
        self.acked = []
        self.nacked = []

    def basic_ack(self, delivery_tag, **kwargs):
        self.acked.append(delivery_tag)

    def basic_nack(self, delivery_tag, requeue=False, **kwargs):
        self.nacked.append((delivery_tag, requeue))


class _FakeMethod:
    def __init__(self, tag: int) -> None:
        self.delivery_tag = tag


class _OkBackend:
    """Fake _backend that responds 200 to any callback."""

    def __call__(self, method, path, *, json_body=None):
        return httpx.Response(200, json={"data": {"primaryFocus": "SLEEP"}})


class _StructuredBackend:
    """Routes responses by the path segment: claim/complete/fail."""

    def __init__(self, claim=200, complete=200, fail=200) -> None:
        self.claim = claim
        self.complete = complete
        self.fail = fail
        self.calls = []

    def __call__(self, method, path, *, json_body=None):
        self.calls.append(path)
        segment = path.rsplit("/", 1)[-1]
        if segment == "claim":
            status = self.claim
            json_payload = {"data": {"primaryFocus": "SLEEP"}} if status == 200 else None
        elif segment == "complete":
            status = self.complete
            json_payload = {"ok": True} if status == 200 else None
        else:
            status = self.fail
            json_payload = {"ok": True} if status == 200 else None
        return httpx.Response(status, json=json_payload)


class _AiResult:
    def __init__(self, exc: Exception | None = None) -> None:
        self.exc = exc

    async def analyze_job(self, scores):
        if self.exc:
            raise self.exc
        return {"aiInsight": "Some good insight text here.", "evidenceSources": ["src:1"]}


@pytest.fixture(autouse=True)
def _fast_retries(monkeypatch):
    """Keep retry/backoff tests quick by collapsing attempts and sleep."""
    monkeypatch.setattr(settings, "callback_attempts", 1)
    monkeypatch.setattr(settings, "callback_backoff_seconds", 0)


def _with_ai(monkeypatch, exc=None):
    monkeypatch.setattr(mq_consumer.ai_router, "analyze_job", _AiResult(exc).analyze_job)


# ------------------------------------------------------------------ happy path

def test_process_job_claims_analyzes_completes(monkeypatch):
    backend = _StructuredBackend()
    monkeypatch.setattr(mq_consumer, "_backend", backend)
    _with_ai(monkeypatch)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK
    assert backend.calls[0].endswith("/claim")
    assert backend.calls[1].endswith("/complete")
    assert len(backend.calls) == 2


# ----------------------------------------------------------------- failure paths

def test_process_job_reports_failure_when_llm_raises(monkeypatch):
    backend = _StructuredBackend()
    monkeypatch.setattr(mq_consumer, "_backend", backend)
    _with_ai(monkeypatch, exc=RuntimeError("gemini down"))

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK
    assert "fail" in backend.calls[-1]


def test_process_job_reports_failure_when_backend_rejects_complete(monkeypatch):
    backend = _StructuredBackend(complete=400)
    monkeypatch.setattr(mq_consumer, "_backend", backend)
    _with_ai(monkeypatch)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK
    assert "fail" in backend.calls[-1]


def test_process_job_acks_conflict_without_failing_retried_job(monkeypatch):
    """complete 409 (job retried/swept under us) must NOT call fail, so a
    re-enqueued job is never clobbered back to FAILED."""
    backend = _StructuredBackend(complete=409)
    monkeypatch.setattr(mq_consumer, "_backend", backend)
    _with_ai(monkeypatch)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK
    assert all("fail" not in call for call in backend.calls)


def test_process_job_acks_on_permanent_claim_conflict(monkeypatch):
    backend = _StructuredBackend(claim=409)
    monkeypatch.setattr(mq_consumer, "_backend", backend)
    _with_ai(monkeypatch)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK
    assert len(backend.calls) == 1


def test_process_job_acks_on_missing_job_404(monkeypatch):
    backend = _StructuredBackend(claim=404)
    monkeypatch.setattr(mq_consumer, "_backend", backend)
    _with_ai(monkeypatch)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK


def test_process_job_requeues_when_backend_unreachable(monkeypatch):
    def boom(method, path, *, json_body=None):
        raise httpx.ConnectError("broker not there")

    monkeypatch.setattr(mq_consumer, "_backend", boom)
    _with_ai(monkeypatch)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == REQUEUE


def test_process_job_requeues_on_5xx_complete(monkeypatch):
    monkeypatch.setattr(mq_consumer, "_backend", _StructuredBackend(complete=502))
    _with_ai(monkeypatch)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == REQUEUE


# ---------------------------------------------------------------- on_message

def test_on_message_acks_on_success(monkeypatch):
    monkeypatch.setattr(mq_consumer, "_run_job", lambda job_id: ACK)
    ch, method = _FakeChannel(), _FakeMethod(7)

    mq_consumer._on_message(ch, method, None, _job_payload())

    assert ch.acked == [7]
    assert ch.nacked == []


def test_on_message_nacks_with_requeue_on_retryable_outcome(monkeypatch):
    monkeypatch.setattr(mq_consumer, "_run_job", lambda job_id: REQUEUE)
    ch, method = _FakeChannel(), _FakeMethod(7)

    mq_consumer._on_message(ch, method, None, _job_payload())

    assert ch.acked == []
    assert ch.nacked == [(7, True)]


def test_on_message_nacks_malformed_payload():
    ch, method = _FakeChannel(), _FakeMethod(7)

    mq_consumer._on_message(ch, method, None, b"not json")

    assert ch.acked == []
    assert ch.nacked == [(7, False)]


# ------------------------------------------------------------------- helpers

def test_is_transient_only_marks_5xx():
    assert mq_consumer._is_transient(httpx.Response(502))
    assert mq_consumer._is_transient(httpx.Response(500))
    assert not mq_consumer._is_transient(httpx.Response(400))
    assert not mq_consumer._is_transient(httpx.Response(409))
    assert not mq_consumer._is_transient(httpx.Response(200))


def test_backend_with_retry_retries_transport_errors(monkeypatch):
    calls = {"n": 0}

    def flaky(method, path, *, json_body=None):
        calls["n"] += 1
        raise httpx.ConnectError("flap")

    monkeypatch.setattr(mq_consumer, "_backend", flaky)
    monkeypatch.setattr(settings, "callback_attempts", 3)
    monkeypatch.setattr(settings, "callback_backoff_seconds", 0)

    response, error = mq_consumer._backend_with_retry("POST", "/x")

    assert response is None
    assert calls["n"] == 3
    assert "flap" in error


def test_backend_with_retry_does_not_retry_4xx(monkeypatch):
    calls = {"n": 0}

    def four_hundred(method, path, *, json_body=None):
        calls["n"] += 1
        return httpx.Response(400)

    monkeypatch.setattr(mq_consumer, "_backend", four_hundred)
    monkeypatch.setattr(settings, "callback_attempts", 3)

    response, error = mq_consumer._backend_with_retry("POST", "/x")

    assert response.status_code == 400
    assert error is None
    assert calls["n"] == 1


# ------------------------------------------------------------------- LLM failure / retry exhaustion

def test_process_job_reports_failure_when_llm_raises(monkeypatch):
    """LLM raises exception -> report failure -> ack (job marked FAILED in backend)."""
    backend = _StructuredBackend(claim=200, complete=200, fail=200)
    monkeypatch.setattr(mq_consumer, "_backend", backend)

    async def failing_analyze(scores):
        raise RuntimeError("LLM timeout")
    monkeypatch.setattr(mq_consumer.ai_router, "analyze_job", failing_analyze)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK
    assert "fail" in backend.calls[-1]


def test_process_job_requeues_when_llm_returns_invalid_output(monkeypatch):
    """LLM returns invalid JSON -> validation fails -> report failure -> ack."""
    backend = _StructuredBackend(claim=200, complete=400, fail=200)
    monkeypatch.setattr(mq_consumer, "_backend", backend)

    async def bad_analyze(scores):
        return {"aiInsight": "x", "evidenceSources": []}  # too short
    monkeypatch.setattr(mq_consumer.ai_router, "analyze_job", bad_analyze)

    outcome = asyncio.run(mq_consumer._process_job("job-1"))

    assert outcome == ACK
    assert "fail" in backend.calls[-1]


def test_on_message_handles_exception_without_requeue_forever(monkeypatch):
    """Unhandled exception in _run_job -> nack without requeue (bounded retries)."""
    monkeypatch.setattr(mq_consumer, "_run_job", lambda job_id: (_ for _ in ()).throw(RuntimeError("boom")))
    ch, method = _FakeChannel(), _FakeMethod(7)

    mq_consumer._on_message(ch, method, None, _job_payload())

    assert ch.acked == []
    assert ch.nacked == [(7, False)]  # requeue=False prevents infinite loop