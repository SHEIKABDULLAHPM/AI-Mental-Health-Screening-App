"""Inbound auth: /api/v1 must only be reachable by the backend when enabled."""

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)


def _risk_payload():
    return {
        "screening_score": {"phq9": 4},
        "contextual_flags": [],
    }


def test_api_is_open_when_inbound_auth_disabled(monkeypatch):
    monkeypatch.setattr(settings, "inbound_auth_required", False)

    resp = client.post("/api/v1/risk/assess", json=_risk_payload())

    assert resp.status_code == 200


def test_api_rejects_missing_key_when_enabled(monkeypatch):
    monkeypatch.setattr(settings, "inbound_auth_required", True)

    resp = client.post("/api/v1/risk/assess", json=_risk_payload())

    assert resp.status_code == 401
    assert "internal API key" in resp.json()["detail"]


def test_api_rejects_wrong_key_when_enabled(monkeypatch):
    monkeypatch.setattr(settings, "inbound_auth_required", True)

    resp = client.post(
        "/api/v1/risk/assess",
        json=_risk_payload(),
        headers={"X-Internal-Api-Key": "wrong-key"},
    )

    assert resp.status_code == 401


def test_api_accepts_shared_key_when_enabled(monkeypatch):
    monkeypatch.setattr(settings, "inbound_auth_required", True)

    resp = client.post(
        "/api/v1/risk/assess",
        json=_risk_payload(),
        headers={"X-Internal-Api-Key": settings.internal_api_key},
    )

    assert resp.status_code == 200


def test_health_stays_public_when_enabled(monkeypatch):
    monkeypatch.setattr(settings, "inbound_auth_required", True)

    resp = client.get("/health")

    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
