---
name: langgraph-hitl-node
description: Use when adding or modifying LangGraph state, nodes, interrupt() / Command(resume=...), AsyncSqliteSaver checkpointing, SSE event streaming, or idempotent SQLite ledger commits in backend/. Do not use for Flutter-only UI tasks.
---

# LangGraph HITL & Idempotent Commit Node Workflow

## Before You Start

- Read `AGENTS.md` and `IMPLEMENTATION_PLAN.md`.
- Verify side-effect isolation: `Command(resume=...)` re-runs the interrupted node function from line 1.

## Workflow

1. Keep `human_review_gate` pure up to `interrupt(payload)` — no non-idempotent DB writes or external HTTP mutations before `interrupt()`.
2. Perform work-order creation/update only in `idempotent_commit`, enforcing `(idempotency_key, payload_fingerprint)` uniqueness in SQLite.
3. Add or update async pytest coverage including reopen/restart checkpoint recovery (`AsyncSqliteSaver`).
4. Run validation before reporting completion.

## Validation

- `cd backend && uv run ruff check . && uv run pytest -q`

## Do Not

- Do not use in-memory-only `MemorySaver` as the production/default checkpointer (breaks restart durability).
- Do not hardcode API keys or reference private external repositories.
