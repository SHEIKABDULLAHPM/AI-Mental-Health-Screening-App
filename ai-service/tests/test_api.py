from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_risk_assessment():
    resp = client.post(
        "/api/v1/risk/assess",
        json={"screening_score": {"phq9": 20}, "contextual_flags": ["hopeless"]},
    )
    assert resp.status_code == 200
    assert resp.json()["immediate_care_required"] is True


def test_emotion_analyze():
    resp = client.post("/api/v1/emotion/analyze", json={"text": "I feel hopeless."})
    assert resp.status_code == 200
    assert "emotion" in resp.json()