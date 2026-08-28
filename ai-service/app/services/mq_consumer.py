"""RabbitMQ consumer for asynchronous AI jobs (screening analysis).

Workflow per message:
    1. decode {"jobId": "..."}
    2. claim the job on the backend (returns deterministic scores)
    3. run the AI pipeline (RAG evidence + Gemini structured insight)
    4. post the result back to the backend (complete) or report failure
    5. ack the message when the job state was durably recorded; otherwise
       requeue (with a delay) so a transient backend outage does not lose work.

The job carries its own retry state in Mongo, so a message is never requeued
forever: once the backend's stale-job sweeper passes it is FAILED and acked.
"""
import asyncio
import json
import threading
import time
from typing import Any

import httpx
import pika

from app.config import settings
from app.logging import get_logger
from app.services.ai_router import ai_router

log = get_logger(__name__)

_BACKEND_TIMEOUT = httpx.Timeout(settings.callback_timeout_seconds)

ACK = "ack"
REQUEUE = "requeue"


def _connection_params() -> pika.ConnectionParameters:
    return pika.ConnectionParameters(
        host=settings.rabbitmq_host,
        port=settings.rabbitmq_port,
        credentials=pika.PlainCredentials(settings.rabbitmq_username, settings.rabbitmq_password),
        heartbeat=60,
        blocked_connection_timeout=30,
    )


def _internal_headers() -> dict[str, str]:
    key = settings.internal_api_key
    if not key:
        raise RuntimeError("AI_INTERNAL_API_KEY is not configured on the AI service.")
    return {"X-Internal-Api-Key": key}


def _backend(method: str, path: str, *, json_body: Any | None = None) -> httpx.Response:
    url = f"{settings.backend_internal_url}{path}"
    with httpx.Client(timeout=_BACKEND_TIMEOUT) as client:
        response = client.request(method, url, headers=_internal_headers(), json=json_body)
    return response


def _is_transient(response: httpx.Response) -> bool:
    """Retryable backend responses: transport-level failures and 5xx."""
    return response.status_code >= 500


def _backend_with_retry(method: str, path: str, *, json_body: Any | None = None):
    """Calls the backend retrying transient failures with a short backoff.

    Returns ``(response, None)`` on success or a definitive non-5xx response,
    or ``(None, error)`` once all attempts are exhausted.
    """
    attempts = max(1, settings.callback_attempts)
    last_error: str | None = None
    for attempt in range(attempts):
        try:
            response = _backend(method, path, json_body=json_body)
        except httpx.HTTPError as exc:
            last_error = str(exc)
        else:
            if not _is_transient(response):
                return (response, None)
            last_error = f"HTTP {response.status_code}"
        if attempt < attempts - 1:
            time.sleep(settings.callback_backoff_seconds * (attempt + 1))
    return (None, last_error)


def _run_job(job_id: str) -> str:
    """Synchronous entry point executed by the consumer thread."""
    return asyncio.run(_process_job(job_id))


async def _process_job(job_id: str) -> str:
    # 1. Claim the job -> deterministic scores.
    claim, c_error = _backend_with_retry("POST", f"/ai-analysis/{job_id}/claim")
    if claim is None:
        log.warning("job_claim_unreachable", jobId=job_id, error=c_error)
        return REQUEUE
    if claim.status_code in (401, 403, 404, 409):
        # Permanent routing/auth/state conflicts must not hot-loop the queue.
        log.warning("job_claim_rejected", jobId=job_id, status=claim.status_code,
                    body=claim.text[:300])
        return ACK
    if claim.status_code != 200:
        log.warning("job_claim_failed", jobId=job_id, status=claim.status_code,
                    body=claim.text[:300])
        return REQUEUE
    scores = claim.json().get("data")

    # 3. Run the AI pipeline (RAG evidence + LLM insight).
    try:
        result = await ai_router.analyze_job(scores or {})
    except Exception as exc:  # noqa: BLE001
        log.error("job_processing_failed", jobId=job_id, error=str(exc))
        return _report_failure(job_id, str(exc))

    # 4. Post the completed result.
    complete, c2_error = _backend_with_retry(
        "POST", f"/ai-analysis/{job_id}/complete",
        json_body={"aiInsight": result["aiInsight"], "evidenceSources": result["evidenceSources"]},
    )
    if complete is None:
        log.warning("job_complete_unreachable", jobId=job_id, error=c2_error)
        return REQUEUE
    if complete.status_code == 409:
        # State changed under us: the job was retried (back to QUEUED), failed
        # by the stale-job sweeper, or completed by another worker. Nothing to
        # do - failing it would clobber the new round and orphan its message.
        log.warning("job_complete_conflict", jobId=job_id, body=complete.text[:300])
        return ACK
    if complete.status_code != 200:
        # The backend rejected the payload (e.g. server-side validation) - the
        # job is reported FAILED so the owner can retry through the UI.
        log.warning("job_complete_failed", jobId=job_id, status=complete.status_code,
                    body=complete.text[:300])
        return _report_failure(job_id, "Backend rejected the AI result.")
    log.info("job_completed", jobId=job_id)
    return ACK


def _report_failure(job_id: str, error: str) -> str:
    body = {"error": error[:500]}
    fail, f_error = _backend_with_retry("POST", f"/ai-analysis/{job_id}/fail", json_body=body)
    if fail is None:
        log.exception("job_fail_report_unreachable", jobId=job_id, error=f_error)
        return REQUEUE
    if fail.status_code not in (200, 404, 409):
        log.warning("job_fail_reported_error", jobId=job_id, status=fail.status_code)
    return ACK


def _on_message(ch, method, properties, body):
    try:
        payload = json.loads(body)
        job_id = payload.get("jobId")
        if not job_id:
            log.warning("message_missing_job_id", body=body[:300])
            ch.basic_ack(delivery_tag=method.delivery_tag)
            return
        log.info("task_received", jobId=job_id)
        outcome = _run_job(job_id)
        if outcome == REQUEUE:
            # Backend is unreachable right now; give the sweeper time, then
            # redeliver. Public health recovers via the backend stale-job sweep.
            log.warning("task_requeue_delayed", jobId=job_id)
            time.sleep(settings.callback_backoff_seconds)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        else:
            ch.basic_ack(delivery_tag=method.delivery_tag)
    except Exception:
        log.exception("task_failed")
        # Do not requeue forever; the job carries its own retry state in Mongo.
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)


def _consume_loop() -> None:
    """Blocking consumer with automatic reconnection.

    The connection is retried forever with a short backoff so a transient
    RabbitMQ outage (e.g. RabbitMQ still warming up while the AI service
    boots) never permanently kills the worker. Each iteration creates a
    fresh channel; `start_consuming()` returns/raises only on disconnect.
    """
    while True:
        connection = None
        try:
            connection = pika.BlockingConnection(_connection_params())
            channel = connection.channel()
            channel.queue_declare(queue=settings.ai_tasks_queue, durable=True)
            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(settings.ai_tasks_queue, on_message_callback=_on_message)
            log.info("consumer_started", queue=settings.ai_tasks_queue)
            channel.start_consuming()
        except Exception:  # noqa: BLE001
            log.exception("consumer_connection_failed", retrying=True)
        finally:
            if connection is not None:
                try:
                    connection.close()
                except Exception:  # noqa: BLE001
                    pass
        # Backoff before reconnecting so a downed broker is not hot-polled.
        time.sleep(settings.callback_backoff_seconds)


def start_consumer() -> None:
    """Launch the background consumer thread (non-blocking, daemon)."""
    thread = threading.Thread(target=_consume_loop, daemon=True, name="mq-consumer")
    thread.start()