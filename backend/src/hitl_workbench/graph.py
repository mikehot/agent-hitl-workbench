"""Stateful LangGraph HITL workflow with AsyncSqliteSaver and side-effect isolation."""

from __future__ import annotations

import asyncio
import operator
import time
from pathlib import Path
from typing import Annotated, Any, Literal, TypedDict
from uuid import uuid4

import aiosqlite
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, interrupt

from hitl_workbench.config import Settings
from hitl_workbench.fixtures import get_fixture
from hitl_workbench.guards import compute_ticket_diffs, evaluate_guards, has_blocker
from hitl_workbench.ledger import WorkbenchLedger, utc_now_iso
from hitl_workbench.providers import TicketExtractor, build_extractor
from hitl_workbench.schemas import (
    EvalRegressionCase,
    ExtractedTicket,
    GuardFlag,
    InterruptPayload,
    NodeTraceEvent,
    ResumeDecisionRequest,
    RunSnapshot,
)


class InvalidHumanOverrideError(ValueError):
    """Raised when a human approves a ticket still violating hard invariants."""


class GraphState(TypedDict, total=False):
    thread_id: str
    fixture_id: str
    doc_title: str
    source_doc_key: str
    tenant_id: str
    raw_ticket: dict[str, Any]
    final_ticket: dict[str, Any]
    guard_flags: list[dict[str, Any]]
    review_action: Literal["auto", "approve", "reject"]
    reviewer_note: str
    work_order_id: str
    idempotent_reused: bool
    eval_case_id: str
    node_trace: Annotated[list[dict[str, Any]], operator.add]


# Hard invariants that even human edits must satisfy before committing to work_orders
_NON_WAIVABLE_CODES = frozenset(
    {
        "LINE_ITEM_SUBTOTAL_MISMATCH",
        "PARTS_SUM_MISMATCH",
        "ARITHMETIC_MISMATCH",
        "MISSING_CUSTOMER_NAME",
        "AMBIGUOUS_UNIT_ADDRESS",
        "PROMPT_INJECTION_SUSPECTED",
    }
)


class WorkbenchRuntime:
    """Manages SQLite checkpointer, ledger, compiled LangGraph, and per-thread SSE subscribers."""

    def __init__(
        self,
        settings: Settings,
        extractor: TicketExtractor | None = None,
    ) -> None:
        self.settings = settings
        self.extractor = extractor or build_extractor(settings)
        self.db_path = Path(settings.sqlite_path)
        self.ledger = WorkbenchLedger(self.db_path)
        self._checkpoint_conn: aiosqlite.Connection | None = None
        self._saver: AsyncSqliteSaver | None = None
        self._graph: Any = None
        self._subscribers: dict[str, list[asyncio.Queue[NodeTraceEvent | None]]] = {}

        # Observable counters for verifying LangGraph node re-execution vs single commit
        self.gate_entry_count: int = 0
        self.commit_execution_count: int = 0

    async def start(self) -> None:
        await self.ledger.setup()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._checkpoint_conn = await aiosqlite.connect(self.db_path)
        self._saver = AsyncSqliteSaver(self._checkpoint_conn)
        await self._saver.setup()
        self._graph = self._build_graph().compile(checkpointer=self._saver)

    async def close(self) -> None:
        if self._checkpoint_conn is not None:
            await self._checkpoint_conn.close()
            self._checkpoint_conn = None

    def subscribe(self, thread_id: str) -> asyncio.Queue[NodeTraceEvent | None]:
        queue: asyncio.Queue[NodeTraceEvent | None] = asyncio.Queue()
        self._subscribers.setdefault(thread_id, []).append(queue)
        return queue

    def unsubscribe(self, thread_id: str, queue: asyncio.Queue[NodeTraceEvent | None]) -> None:
        queues = self._subscribers.get(thread_id, [])
        if queue in queues:
            queues.remove(queue)

    def _publish_trace(self, thread_id: str, event: NodeTraceEvent) -> None:
        for queue in self._subscribers.get(thread_id, []):
            queue.put_nowait(event)

    def _close_stream(self, thread_id: str) -> None:
        for queue in self._subscribers.get(thread_id, []):
            queue.put_nowait(None)

    def _build_graph(self) -> StateGraph:
        builder = StateGraph(GraphState)

        async def ingest_extract(state: GraphState) -> GraphState:
            t0 = time.perf_counter()
            fx = get_fixture(state["fixture_id"])
            ticket = await self.extractor.extract(fx)
            elapsed = round((time.perf_counter() - t0) * 1000, 2)
            ev = NodeTraceEvent(
                node="ingest_extract",
                status="completed",
                duration_ms=elapsed,
                detail=f"抽取完成 ({ticket.doc_type}, 置信度={ticket.confidence:.2f})",
                timestamp=utc_now_iso(),
            )
            self._publish_trace(state["thread_id"], ev)
            return {
                "doc_title": fx.title,
                "source_doc_key": fx.source_doc_key,
                "raw_ticket": ticket.model_dump(),
                "final_ticket": ticket.model_dump(),
                "node_trace": [ev.model_dump()],
            }

        async def deterministic_guard(state: GraphState) -> GraphState:
            t0 = time.perf_counter()
            ticket = ExtractedTicket.model_validate(state["raw_ticket"])
            flags = evaluate_guards(ticket)
            blocked = has_blocker(flags)
            elapsed = round((time.perf_counter() - t0) * 1000, 2)
            codes = ", ".join(f.code for f in flags) if flags else "CLEAN"
            ev = NodeTraceEvent(
                node="deterministic_guard",
                status="completed",
                duration_ms=elapsed,
                detail=f"规则门禁判定: {'拦截挂起' if blocked else '自动放行'} [{codes}]",
                timestamp=utc_now_iso(),
            )
            self._publish_trace(state["thread_id"], ev)
            return {
                "guard_flags": [f.model_dump() for f in flags],
                "review_action": "approve" if not blocked else "auto",
                "node_trace": [ev.model_dump()],
            }

        def route_after_guard(
            state: GraphState,
        ) -> Literal["human_review_gate", "idempotent_commit"]:
            flags = [GuardFlag.model_validate(f) for f in state.get("guard_flags", [])]
            if has_blocker(flags):
                return "human_review_gate"
            return "idempotent_commit"

        async def human_review_gate(state: GraphState) -> GraphState:
            # INVARIANT: Zero DB/external side effects before interrupt()!
            # LangGraph re-runs this function from the top when Command(resume=...) is called.
            self.gate_entry_count += 1
            raw_ticket = ExtractedTicket.model_validate(state["raw_ticket"])
            flags = [GuardFlag.model_validate(f) for f in state.get("guard_flags", [])]
            payload = InterruptPayload(
                reason="deterministic_guard_blocked",
                doc_id=state["fixture_id"],
                doc_title=state["doc_title"],
                guard_flags=flags,
                proposed_ticket=raw_ticket,
            )

            decision_raw: dict[str, Any] = interrupt(payload.model_dump())

            t0 = time.perf_counter()
            decision = ResumeDecisionRequest.model_validate(decision_raw)
            if decision.action == "reject":
                elapsed = round((time.perf_counter() - t0) * 1000, 2)
                ev = NodeTraceEvent(
                    node="human_review_gate",
                    status="completed",
                    duration_ms=elapsed,
                    detail=f"人工驳回单据: {decision.reviewer_note or '无备注'}",
                    timestamp=utc_now_iso(),
                )
                self._publish_trace(state["thread_id"], ev)
                return {
                    "review_action": "reject",
                    "reviewer_note": decision.reviewer_note,
                    "node_trace": [ev.model_dump()],
                }

            candidate = decision.edited_ticket or raw_ticket
            post_flags = evaluate_guards(candidate)
            hard_violations = [f for f in post_flags if f.code in _NON_WAIVABLE_CODES]
            if hard_violations:
                joined = "; ".join(f"{f.code}: {f.message}" for f in hard_violations)
                raise InvalidHumanOverrideError(
                    f"提交的人工修正仍违反硬性业务不变量，请修正后再审批：{joined}"
                )

            elapsed = round((time.perf_counter() - t0) * 1000, 2)
            ev = NodeTraceEvent(
                node="human_review_gate",
                status="completed",
                duration_ms=elapsed,
                detail=f"人工复核通过 ({decision.reviewer_note or '已确认字段'})",
                timestamp=utc_now_iso(),
            )
            self._publish_trace(state["thread_id"], ev)
            return {
                "review_action": "approve",
                "final_ticket": candidate.model_dump(),
                "reviewer_note": decision.reviewer_note,
                "node_trace": [ev.model_dump()],
            }

        def route_after_human(
            state: GraphState,
        ) -> Literal["idempotent_commit", "mark_rejected"]:
            if state.get("review_action") == "reject":
                return "mark_rejected"
            return "idempotent_commit"

        async def idempotent_commit(state: GraphState) -> GraphState:
            t0 = time.perf_counter()
            self.commit_execution_count += 1
            final_ticket = ExtractedTicket.model_validate(state["final_ticket"])
            record, reused = await self.ledger.commit_work_order(
                thread_id=state["thread_id"],
                doc_id=state["fixture_id"],
                tenant_id=state["tenant_id"],
                source_doc_key=state["source_doc_key"],
                ticket=final_ticket,
            )
            elapsed = round((time.perf_counter() - t0) * 1000, 2)
            ev = NodeTraceEvent(
                node="idempotent_commit",
                status="completed",
                duration_ms=elapsed,
                detail=(
                    f"工单已幂等复用 {record.work_order_id} (replay_hits={record.replay_hits})"
                    if reused
                    else f"工单已创建 {record.work_order_id} (key={record.idempotency_key})"
                ),
                timestamp=utc_now_iso(),
            )
            self._publish_trace(state["thread_id"], ev)
            return {
                "work_order_id": record.work_order_id,
                "idempotent_reused": reused,
                "node_trace": [ev.model_dump()],
            }

        async def export_eval_case(state: GraphState) -> GraphState:
            t0 = time.perf_counter()
            raw_ticket = ExtractedTicket.model_validate(state["raw_ticket"])
            final_ticket = ExtractedTicket.model_validate(state["final_ticket"])
            diffs = compute_ticket_diffs(raw_ticket, final_ticket)
            flags = [GuardFlag.model_validate(f) for f in state.get("guard_flags", [])]

            if not diffs and not flags:
                elapsed = round((time.perf_counter() - t0) * 1000, 2)
                ev = NodeTraceEvent(
                    node="export_eval_case",
                    status="skipped",
                    duration_ms=elapsed,
                    detail="标准自动放行单据无差异，跳过回归样本导出",
                    timestamp=utc_now_iso(),
                )
                self._publish_trace(state["thread_id"], ev)
                return {"node_trace": [ev.model_dump()]}

            case = EvalRegressionCase(
                case_id=f"EVAL-{uuid4().hex[:8].upper()}",
                thread_id=state["thread_id"],
                doc_id=state["fixture_id"],
                doc_type=final_ticket.doc_type,
                guard_codes=[f.code for f in flags],
                field_diffs=diffs,
                raw_extraction=raw_ticket,
                expected_truth=final_ticket,
                reviewer_note=state.get("reviewer_note", ""),
                created_at=utc_now_iso(),
            )
            saved = await self.ledger.save_eval_case(case)
            elapsed = round((time.perf_counter() - t0) * 1000, 2)
            ev = NodeTraceEvent(
                node="export_eval_case",
                status="completed",
                duration_ms=elapsed,
                detail=f"已沉淀回归评测样本 {saved.case_id} (字段修正数={len(diffs)})",
                timestamp=utc_now_iso(),
            )
            self._publish_trace(state["thread_id"], ev)
            return {
                "eval_case_id": saved.case_id,
                "node_trace": [ev.model_dump()],
            }

        async def mark_rejected(state: GraphState) -> GraphState:
            ev = NodeTraceEvent(
                node="mark_rejected",
                status="completed",
                duration_ms=0.1,
                detail="单据已归档为人工驳回，未写入工单表",
                timestamp=utc_now_iso(),
            )
            self._publish_trace(state["thread_id"], ev)
            return {"node_trace": [ev.model_dump()]}

        builder.add_node("ingest_extract", ingest_extract)
        builder.add_node("deterministic_guard", deterministic_guard)
        builder.add_node("human_review_gate", human_review_gate)
        builder.add_node("idempotent_commit", idempotent_commit)
        builder.add_node("export_eval_case", export_eval_case)
        builder.add_node("mark_rejected", mark_rejected)

        builder.add_edge(START, "ingest_extract")
        builder.add_edge("ingest_extract", "deterministic_guard")
        builder.add_conditional_edges(
            "deterministic_guard",
            route_after_guard,
            {
                "human_review_gate": "human_review_gate",
                "idempotent_commit": "idempotent_commit",
            },
        )
        builder.add_conditional_edges(
            "human_review_gate",
            route_after_human,
            {
                "idempotent_commit": "idempotent_commit",
                "mark_rejected": "mark_rejected",
            },
        )
        builder.add_edge("idempotent_commit", "export_eval_case")
        builder.add_edge("export_eval_case", END)
        builder.add_edge("mark_rejected", END)
        return builder

    async def start_run(
        self,
        *,
        fixture_id: str,
        thread_id: str | None = None,
        tenant_id: str | None = None,
    ) -> RunSnapshot:
        fx = get_fixture(fixture_id)
        tid = thread_id or f"run-{uuid4().hex[:10]}"
        tenant = tenant_id or fx.tenant_id
        cfg = {"configurable": {"thread_id": tid}}

        result: dict[str, Any] = await self._graph.ainvoke(
            {
                "thread_id": tid,
                "fixture_id": fx.fixture_id,
                "tenant_id": tenant,
                "node_trace": [],
            },
            cfg,
        )
        snapshot = self._state_to_snapshot(result)
        if snapshot.status == "interrupted":
            pause_ev = NodeTraceEvent(
                node="human_review_gate",
                status="interrupted",
                duration_ms=0.1,
                detail="已写入 SQLite Checkpoint 并挂起等待人工审批",
                timestamp=utc_now_iso(),
            )
            snapshot.node_trace.append(pause_ev)
            self._publish_trace(tid, pause_ev)
        self._close_stream(tid)
        await self.ledger.upsert_run_snapshot(snapshot)
        return snapshot

    async def resume_run(
        self,
        thread_id: str,
        decision: ResumeDecisionRequest,
    ) -> RunSnapshot:
        existing = await self.ledger.get_run_snapshot(thread_id)
        if existing is None:
            raise KeyError(f"Unknown thread_id: {thread_id}")
        if existing.status != "interrupted":
            raise ValueError(f"Run {thread_id} is in status '{existing.status}', cannot resume.")

        # Pre-validate before Command(resume=...) so invalid edits never pollute SQLite
        # checkpoint scratchpad writes (in LangGraph 1.2, raising *after* interrupt() leaves
        # the consumed resume value in checkpoint writes and replays it on the next call).
        if decision.action == "approve":
            candidate = decision.edited_ticket or existing.extracted_ticket
            if candidate is None:
                raise InvalidHumanOverrideError("Missing candidate ticket for approval.")
            post_flags = evaluate_guards(candidate)
            hard_violations = [f for f in post_flags if f.code in _NON_WAIVABLE_CODES]
            if hard_violations:
                joined = "; ".join(f"{f.code}: {f.message}" for f in hard_violations)
                raise InvalidHumanOverrideError(
                    f"提交的人工修正仍违反硬性业务不变量，请修正后再审批：{joined}"
                )

        cfg = {"configurable": {"thread_id": thread_id}}
        result: dict[str, Any] = await self._graph.ainvoke(
            Command(resume=decision.model_dump()),
            cfg,
        )
        snapshot = self._state_to_snapshot(result)
        self._close_stream(thread_id)
        await self.ledger.upsert_run_snapshot(snapshot)
        return snapshot

    def _state_to_snapshot(self, result: dict[str, Any]) -> RunSnapshot:
        interrupted_items = result.get("__interrupt__")
        interrupt_payload = (
            InterruptPayload.model_validate(interrupted_items[0].value)
            if interrupted_items
            else None
        )
        if interrupt_payload is not None:
            status: Literal["completed", "interrupted", "rejected"] = "interrupted"
        elif result.get("review_action") == "reject":
            status = "rejected"
        else:
            status = "completed"

        raw_t = (
            ExtractedTicket.model_validate(result["raw_ticket"]) if "raw_ticket" in result else None
        )
        final_t = (
            ExtractedTicket.model_validate(result["final_ticket"])
            if "final_ticket" in result and status == "completed"
            else None
        )
        return RunSnapshot(
            thread_id=result["thread_id"],
            doc_id=result["fixture_id"],
            doc_title=result.get("doc_title", result["fixture_id"]),
            tenant_id=result["tenant_id"],
            status=status,
            extracted_ticket=raw_t,
            final_ticket=final_t,
            guard_flags=[GuardFlag.model_validate(f) for f in result.get("guard_flags", [])],
            interrupt_payload=interrupt_payload,
            work_order_id=result.get("work_order_id"),
            idempotent_reused=bool(result.get("idempotent_reused", False)),
            eval_case_id=result.get("eval_case_id"),
            reviewer_note=result.get("reviewer_note", ""),
            node_trace=[NodeTraceEvent.model_validate(ev) for ev in result.get("node_trace", [])],
            updated_at=utc_now_iso(),
        )
