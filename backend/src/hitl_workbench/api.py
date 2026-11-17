"""FastAPI HTTP + SSE application exposing the Stateful HITL Workbench."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse

from hitl_workbench.config import Settings
from hitl_workbench.fixtures import SYNTHETIC_FIXTURES, get_fixture
from hitl_workbench.graph import InvalidHumanOverrideError, WorkbenchRuntime
from hitl_workbench.ledger import IdempotencyConflictError
from hitl_workbench.providers import TicketExtractor
from hitl_workbench.schemas import (
    EvalRegressionCase,
    FixtureSummary,
    ResumeDecisionRequest,
    RunSnapshot,
    StartRunRequest,
    WorkOrderRecord,
)


def create_app(
    settings: Settings | None = None,
    extractor: TicketExtractor | None = None,
) -> FastAPI:
    cfg = settings or Settings()
    runtime = WorkbenchRuntime(cfg, extractor=extractor)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        await runtime.start()
        app.state.runtime = runtime
        try:
            yield
        finally:
            await runtime.close()

    app = FastAPI(
        title="Agent HITL Workbench API",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cfg.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    def _rt(request: Request) -> WorkbenchRuntime:
        return request.app.state.runtime

    @app.get("/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok", "mode": cfg.mode}

    @app.get("/api/v1/fixtures", response_model=list[FixtureSummary])
    async def list_fixtures() -> list[FixtureSummary]:
        return [fx.to_summary() for fx in SYNTHETIC_FIXTURES]

    @app.get("/api/v1/fixtures/{fixture_id}", response_model=FixtureSummary)
    async def read_fixture(fixture_id: str) -> FixtureSummary:
        try:
            return get_fixture(fixture_id).to_summary()
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    @app.post("/api/v1/runs", response_model=RunSnapshot)
    async def create_run(body: StartRunRequest, request: Request) -> RunSnapshot:
        rt = _rt(request)
        try:
            return await rt.start_run(
                fixture_id=body.fixture_id,
                thread_id=body.thread_id,
                tenant_id=body.tenant_id,
            )
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except IdempotencyConflictError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.get("/api/v1/runs", response_model=list[RunSnapshot])
    async def list_runs(request: Request) -> list[RunSnapshot]:
        return await _rt(request).ledger.list_run_snapshots()

    @app.get("/api/v1/runs/{thread_id}", response_model=RunSnapshot)
    async def get_run(thread_id: str, request: Request) -> RunSnapshot:
        snap = await _rt(request).ledger.get_run_snapshot(thread_id)
        if snap is None:
            raise HTTPException(status_code=404, detail=f"Run not found: {thread_id}")
        return snap

    @app.get("/api/v1/runs/{thread_id}/events")
    async def stream_run_events(thread_id: str, request: Request) -> StreamingResponse:
        rt = _rt(request)
        snap = await rt.ledger.get_run_snapshot(thread_id)
        if snap is None:
            raise HTTPException(status_code=404, detail=f"Run not found: {thread_id}")

        async def _event_gen() -> AsyncIterator[str]:
            # Emit already recorded trace events first so reconnecting clients never miss history
            for ev in snap.node_trace:
                yield f"event: node_trace\ndata: {ev.model_dump_json()}\n\n"
            yield f"event: snapshot\ndata: {snap.model_dump_json()}\n\n"

        return StreamingResponse(_event_gen(), media_type="text/event-stream")

    @app.post("/api/v1/runs/{thread_id}/resume", response_model=RunSnapshot)
    async def resume_run(
        thread_id: str,
        body: ResumeDecisionRequest,
        request: Request,
    ) -> RunSnapshot:
        rt = _rt(request)
        try:
            return await rt.resume_run(thread_id, body)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except InvalidHumanOverrideError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except IdempotencyConflictError as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.get("/api/v1/work-orders", response_model=list[WorkOrderRecord])
    async def list_work_orders(request: Request) -> list[WorkOrderRecord]:
        return await _rt(request).ledger.list_work_orders()

    @app.get("/api/v1/eval-cases", response_model=list[EvalRegressionCase])
    async def list_eval_cases(request: Request) -> list[EvalRegressionCase]:
        return await _rt(request).ledger.list_eval_cases()

    @app.get("/api/v1/eval-cases/export.jsonl", response_class=PlainTextResponse)
    async def export_eval_jsonl(request: Request) -> PlainTextResponse:
        content = await _rt(request).ledger.export_eval_jsonl()
        return PlainTextResponse(
            content=content,
            media_type="application/x-ndjson; charset=utf-8",
        )

    return app
