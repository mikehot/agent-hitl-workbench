"""FastAPI HTTP/SSE contract tests and OpenAI-compatible VLM provider tests."""

import json
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

import httpx

from hitl_workbench.api import create_app
from hitl_workbench.config import Settings
from hitl_workbench.fixtures import get_fixture
from hitl_workbench.providers import OpenAICompatibleTicketExtractor


@asynccontextmanager
async def _test_client(tmp_path: Path) -> AsyncIterator[httpx.AsyncClient]:
    cfg = Settings(mode="replay", sqlite_path=str(tmp_path / "api_test.db"))
    app = create_app(cfg)
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


async def test_healthz_and_fixtures_endpoints(tmp_path: Path) -> None:
    async with _test_client(tmp_path) as client:
        hz = await client.get("/healthz")
        assert hz.status_code == 200
        assert hz.json() == {"status": "ok", "mode": "replay"}

        fxs = await client.get("/api/v1/fixtures")
        assert fxs.status_code == 200
        items = fxs.json()
        assert len(items) == 8
        assert items[0]["document_svg"].startswith("<svg")

        one = await client.get("/api/v1/fixtures/hitl-01")
        assert one.status_code == 200
        assert one.json()["category"] == "hitl_review"

        missing = await client.get("/api/v1/fixtures/does-not-exist")
        assert missing.status_code == 404


async def test_api_clean_run_and_sse_events(tmp_path: Path) -> None:
    async with _test_client(tmp_path) as client:
        resp = await client.post("/api/v1/runs", json={"fixture_id": "clean-03"})
        assert resp.status_code == 200
        snap = resp.json()
        assert snap["status"] == "completed"
        tid = snap["thread_id"]

        sse = await client.get(f"/api/v1/runs/{tid}/events")
        assert sse.status_code == 200
        assert sse.headers["content-type"].startswith("text/event-stream")
        assert "event: node_trace" in sse.text
        assert "event: snapshot" in sse.text

        runs = await client.get("/api/v1/runs")
        assert len(runs.json()) == 1


async def test_api_hitl_resume_validation_422_409_and_jsonl_export(tmp_path: Path) -> None:
    async with _test_client(tmp_path) as client:
        created = await client.post(
            "/api/v1/runs",
            json={"fixture_id": "hitl-01", "thread_id": "api-hitl-1"},
        )
        assert created.status_code == 200
        snap = created.json()
        assert snap["status"] == "interrupted"

        # 1. Submitting unfixed arithmetic returns HTTP 422
        bad = await client.post(
            "/api/v1/runs/api-hitl-1/resume",
            json={"action": "approve", "edited_ticket": snap["extracted_ticket"]},
        )
        assert bad.status_code == 422

        # 2. Submitting fixed total_fee_cents=20000 succeeds
        edited = dict(snap["extracted_ticket"])
        edited["total_fee_cents"] = 20_000
        good = await client.post(
            "/api/v1/runs/api-hitl-1/resume",
            json={
                "action": "approve",
                "edited_ticket": edited,
                "reviewer_note": "API审阅修正涂改金额",
            },
        )
        assert good.status_code == 200
        assert good.json()["status"] == "completed"

        # 3. Attempting to resume an already completed run returns HTTP 409
        again = await client.post(
            "/api/v1/runs/api-hitl-1/resume",
            json={"action": "approve", "edited_ticket": edited},
        )
        assert again.status_code == 409

        # 4. Verify work order and JSONL regression export
        orders = await client.get("/api/v1/work-orders")
        assert len(orders.json()) == 1
        assert orders.json()[0]["ticket"]["total_fee_cents"] == 20_000

        cases = await client.get("/api/v1/eval-cases")
        assert len(cases.json()) == 1

        jsonl_resp = await client.get("/api/v1/eval-cases/export.jsonl")
        assert jsonl_resp.status_code == 200
        lines = [ln for ln in jsonl_resp.text.strip().splitlines() if ln]
        assert len(lines) == 1
        parsed = json.loads(lines[0])
        assert parsed["expected_truth"]["total_fee_cents"] == 20_000


async def test_api_404_on_unknown_run_and_unknown_fixture_post(tmp_path: Path) -> None:
    async with _test_client(tmp_path) as client:
        assert (await client.get("/api/v1/runs/no-such-run")).status_code == 404
        assert (await client.get("/api/v1/runs/no-such-run/events")).status_code == 404
        assert (
            await client.post(
                "/api/v1/runs/no-such-run/resume",
                json={"action": "reject"},
            )
        ).status_code == 404
        assert (await client.post("/api/v1/runs", json={"fixture_id": "bad-id"})).status_code == 404


async def test_openai_compatible_extractor_sends_reasoning_effort_none_and_strips_fences() -> None:
    captured_body: dict[str, object] = {}
    fx = get_fixture("clean-02")

    def _handler(request: httpx.Request) -> httpx.Response:
        captured_body.update(json.loads(request.content.decode()))
        fenced_json = f"```json\n{fx.replay_extraction.model_dump_json()}\n```"
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": fenced_json}}]},
        )

    cfg = Settings(
        mode="live",
        llm_base_url="http://mock-vlm.local/v1",
        llm_model_id="qwen/qwen3.8-27b",
        llm_reasoning_effort="none",
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(_handler)) as mock_http:
        extractor = OpenAICompatibleTicketExtractor(cfg, client=mock_http)
        out = await extractor.extract(fx)

    assert captured_body["reasoning_effort"] == "none"
    assert captured_body["temperature"] == 0
    assert out == fx.replay_extraction
