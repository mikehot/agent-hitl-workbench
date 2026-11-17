"""Async SQLite ledger for idempotent work orders, run snapshots, and Trace-to-Eval cases."""

from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import aiosqlite

from hitl_workbench.schemas import (
    EvalRegressionCase,
    ExtractedTicket,
    RunSnapshot,
    WorkOrderRecord,
)


class IdempotencyConflictError(Exception):
    """Raised when an existing idempotency_key is replayed with a mutated payload fingerprint."""


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat()


def compute_idempotency_key(tenant_id: str, source_doc_key: str) -> str:
    digest = hashlib.sha256(f"{tenant_id.strip()}:{source_doc_key.strip()}".encode()).hexdigest()
    return f"idem-{digest[:24]}"


def compute_payload_fingerprint(ticket: ExtractedTicket) -> str:
    canonical = json.dumps(
        {
            "doc_type": ticket.doc_type,
            "customer_name": ticket.customer_name.strip(),
            "unit_address": ticket.unit_address.strip(),
            "labor_fee_cents": ticket.labor_fee_cents,
            "parts_fee_cents": ticket.parts_fee_cents,
            "total_fee_cents": ticket.total_fee_cents,
        },
        sort_keys=True,
        ensure_ascii=False,
    )
    return hashlib.sha256(canonical.encode()).hexdigest()[:32]


class WorkbenchLedger:
    """Durable SQLite store isolated from external customer databases."""

    def __init__(self, db_path: str | Path) -> None:
        self.db_path = Path(db_path)

    async def setup(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute("PRAGMA journal_mode=WAL;")
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS work_orders (
                    work_order_id TEXT PRIMARY KEY,
                    thread_id TEXT NOT NULL,
                    doc_id TEXT NOT NULL,
                    tenant_id TEXT NOT NULL,
                    idempotency_key TEXT NOT NULL UNIQUE,
                    payload_fingerprint TEXT NOT NULL,
                    ticket_json TEXT NOT NULL,
                    replay_hits INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL
                )
                """
            )
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS eval_cases (
                    case_id TEXT PRIMARY KEY,
                    thread_id TEXT NOT NULL UNIQUE,
                    doc_id TEXT NOT NULL,
                    case_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """
            )
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS run_snapshots (
                    thread_id TEXT PRIMARY KEY,
                    updated_at TEXT NOT NULL,
                    snapshot_json TEXT NOT NULL
                )
                """
            )
            await db.commit()

    async def commit_work_order(
        self,
        *,
        thread_id: str,
        doc_id: str,
        tenant_id: str,
        source_doc_key: str,
        ticket: ExtractedTicket,
    ) -> tuple[WorkOrderRecord, bool]:
        """Insert a work order or return the existing record if idempotency_key matches.

        Returns `(record, idempotent_reused)`. Raises `IdempotencyConflictError` if the same
        `idempotency_key` is submitted with a different `payload_fingerprint`.
        """
        idem_key = compute_idempotency_key(tenant_id, source_doc_key)
        fingerprint = compute_payload_fingerprint(ticket)

        async with aiosqlite.connect(self.db_path) as db:
            await db.execute("BEGIN IMMEDIATE")
            cursor = await db.execute(
                """
                SELECT work_order_id, thread_id, doc_id, tenant_id, idempotency_key,
                       payload_fingerprint, ticket_json, replay_hits, created_at
                FROM work_orders
                WHERE idempotency_key = ?
                """,
                (idem_key,),
            )
            row = await cursor.fetchone()
            if row is not None:
                existing_fp = row[5]
                if existing_fp != fingerprint:
                    await db.rollback()
                    raise IdempotencyConflictError(
                        f"Idempotency key {idem_key} already committed with fingerprint "
                        f"{existing_fp}, cannot overwrite with {fingerprint}."
                    )
                new_hits = int(row[7]) + 1
                await db.execute(
                    "UPDATE work_orders SET replay_hits = ? WHERE idempotency_key = ?",
                    (new_hits, idem_key),
                )
                await db.commit()
                record = WorkOrderRecord(
                    work_order_id=row[0],
                    thread_id=row[1],
                    doc_id=row[2],
                    tenant_id=row[3],
                    idempotency_key=row[4],
                    payload_fingerprint=existing_fp,
                    ticket=ExtractedTicket.model_validate_json(row[6]),
                    replay_hits=new_hits,
                    created_at=row[8],
                )
                return record, True

            wo_id = f"WO-{uuid4().hex[:10].upper()}"
            now = utc_now_iso()
            record = WorkOrderRecord(
                work_order_id=wo_id,
                thread_id=thread_id,
                doc_id=doc_id,
                tenant_id=tenant_id,
                idempotency_key=idem_key,
                payload_fingerprint=fingerprint,
                ticket=ticket,
                replay_hits=0,
                created_at=now,
            )
            await db.execute(
                """
                INSERT INTO work_orders (
                    work_order_id, thread_id, doc_id, tenant_id, idempotency_key,
                    payload_fingerprint, ticket_json, replay_hits, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
                """,
                (
                    record.work_order_id,
                    record.thread_id,
                    record.doc_id,
                    record.tenant_id,
                    record.idempotency_key,
                    record.payload_fingerprint,
                    record.ticket.model_dump_json(),
                    record.created_at,
                ),
            )
            await db.commit()
            return record, False

    async def list_work_orders(self) -> list[WorkOrderRecord]:
        async with aiosqlite.connect(self.db_path) as db:
            cursor = await db.execute(
                """
                SELECT work_order_id, thread_id, doc_id, tenant_id, idempotency_key,
                       payload_fingerprint, ticket_json, replay_hits, created_at
                FROM work_orders
                ORDER BY created_at DESC
                """
            )
            rows = await cursor.fetchall()
        return [
            WorkOrderRecord(
                work_order_id=r[0],
                thread_id=r[1],
                doc_id=r[2],
                tenant_id=r[3],
                idempotency_key=r[4],
                payload_fingerprint=r[5],
                ticket=ExtractedTicket.model_validate_json(r[6]),
                replay_hits=int(r[7]),
                created_at=r[8],
            )
            for r in rows
        ]

    async def save_eval_case(self, case: EvalRegressionCase) -> EvalRegressionCase:
        async with aiosqlite.connect(self.db_path) as db:
            cursor = await db.execute(
                "SELECT case_json FROM eval_cases WHERE thread_id = ?",
                (case.thread_id,),
            )
            existing = await cursor.fetchone()
            if existing is not None:
                return EvalRegressionCase.model_validate_json(existing[0])

            await db.execute(
                """
                INSERT INTO eval_cases (case_id, thread_id, doc_id, case_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    case.case_id,
                    case.thread_id,
                    case.doc_id,
                    case.model_dump_json(),
                    case.created_at,
                ),
            )
            await db.commit()
            return case

    async def list_eval_cases(self) -> list[EvalRegressionCase]:
        async with aiosqlite.connect(self.db_path) as db:
            cursor = await db.execute("SELECT case_json FROM eval_cases ORDER BY created_at ASC")
            rows = await cursor.fetchall()
        return [EvalRegressionCase.model_validate_json(r[0]) for r in rows]

    async def export_eval_jsonl(self) -> str:
        cases = await self.list_eval_cases()
        if not cases:
            return ""
        return "\n".join(c.model_dump_json() for c in cases) + "\n"

    async def upsert_run_snapshot(self, snapshot: RunSnapshot) -> None:
        async with aiosqlite.connect(self.db_path) as db:
            await db.execute(
                """
                INSERT INTO run_snapshots (thread_id, updated_at, snapshot_json)
                VALUES (?, ?, ?)
                ON CONFLICT(thread_id) DO UPDATE SET
                    updated_at = excluded.updated_at,
                    snapshot_json = excluded.snapshot_json
                """,
                (snapshot.thread_id, snapshot.updated_at, snapshot.model_dump_json()),
            )
            await db.commit()

    async def get_run_snapshot(self, thread_id: str) -> RunSnapshot | None:
        async with aiosqlite.connect(self.db_path) as db:
            cursor = await db.execute(
                "SELECT snapshot_json FROM run_snapshots WHERE thread_id = ?",
                (thread_id,),
            )
            row = await cursor.fetchone()
        if row is None:
            return None
        return RunSnapshot.model_validate_json(row[0])

    async def list_run_snapshots(self) -> list[RunSnapshot]:
        async with aiosqlite.connect(self.db_path) as db:
            cursor = await db.execute(
                "SELECT snapshot_json FROM run_snapshots ORDER BY updated_at DESC"
            )
            rows = await cursor.fetchall()
        return [RunSnapshot.model_validate_json(r[0]) for r in rows]
