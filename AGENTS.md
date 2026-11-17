# agent-hitl-workbench Agent Guide

This repository is the source of truth for **Agent HITL Workbench** — an open-source, MIT-licensed full-stack reference system demonstrating stateful `LangGraph` Human-in-the-Loop (`interrupt` / `Command(resume=...)`) approval, deterministic guardrails, idempotent write-back, and `Trace-to-Eval` regression dataset generation across a Python backend and a Flutter (Web / macOS / Android) workbench.

## Project Role

- Repository layout:
  - `backend/` — Python 3.12+, `FastAPI`, `LangGraph 1.2`, `AsyncSqliteSaver` durable checkpointer, deterministic guardrails, idempotent SQLite work-order ledger, and `Trace-to-Eval` JSONL exporter.
  - `app/` — Flutter 3.44+ (`flutter_riverpod 2.6.x`, `dio 5.x`, decoupled `lib/core/` MVVM kernel) targeting Web (Cloudflare Pages static Live Demo), macOS desktop, and Android device capture.
- Operating modes:
  - `WORKBENCH_MODE=replay` (default): deterministic pre-recorded synthetic fixtures (auto-pass, guard-flagged `interrupt`, adversarial injection trap) for zero-token, zero-latency public interactive demo and CI tests.
  - `WORKBENCH_MODE=live`: OpenAI-compatible multimodal endpoint (local LM Studio `http://127.0.0.1:1234/v1` with `reasoning_effort="none"` or cloud provider).

## External Context — Shared Knowledge Base

- Optional personal engineering knowledge base: `../AI-Vault/` (may be absent on clean clones or CI runners; **never** make builds or tests depend on it).
- **This repository wins on conflict**: current source code, tests, and `IMPLEMENTATION_PLAN.md` take precedence over vault notes.
- Do not modify `../AI-Vault/` during repository work unless the user explicitly asks for vault distillation.

## Primary Engineering Invariants

1. **Side-Effect Isolation Around `interrupt()`**: In `LangGraph`, `Command(resume=...)` re-executes the interrupted node from the top of that function. Never place non-idempotent writes or external mutations before `interrupt()` inside `human_review_gate`; keep mutations in the downstream `idempotent_commit` node guarded by `(idempotency_key, payload_fingerprint)`.
2. **Synthetic Data & Public-Repo Hygiene**: All bundled documents, fixtures, screenshots, and evaluation cases must be 100% synthetic. Never store API keys, tokens, private URLs, customer names, or internal repository references in code, tests, or commit history.
3. **Anti-Bloat Documentation Guard**: Keep documentation concise (`README.md`, `IMPLEMENTATION_PLAN.md`, and single-file evaluation reports when experiments run). Do not proliferate governance/ceremony markdown files.
4. **Git Outward Safety**: Never auto-commit, push, merge, delete branches, or open PRs without explicit user confirmation each time.

## Skill Map (`SKILLS.md`)

Read `SKILLS.md` and load the matching `.agents/skills/<skill-name>/SKILL.md` when working on:
- `langgraph-hitl-node` — stateful graph nodes, `interrupt` / `Command(resume=...)`, SQLite checkpointing, or idempotent ledger writes.
- `flutter-workbench-ui` — Flutter `app/lib/` pages, `BaseViewModel` / `UiState`, SSE/HTTP repository wiring, or responsive 3-pane / mobile layouts.
- `trace-to-eval-export` — human correction capture, `regression_cases.jsonl` export, or offline evaluation harness.
- `verify-before-done` — pre-handoff static analysis, unit/integration tests, and build verification.

## Validation Commands

- Backend lint & format check: `cd backend && uv run ruff check . && uv run ruff format --check .`
- Backend unit & checkpoint tests: `cd backend && uv run pytest -q`
- Flutter static analysis: `cd app && dart analyze lib/`
- Flutter widget/unit tests: `cd app && flutter test`
- Flutter Web static build check (when UI changes touch Web compatibility): `cd app && flutter build web`
