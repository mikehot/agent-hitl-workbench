# agent-hitl-workbench Skills

This catalog maps recurring engineering workflows in `agent-hitl-workbench` to repo-local skills under `.agents/skills/<skill-name>/SKILL.md`.

| skill | use when | read first | validation |
| --- | --- | --- | --- |
| `langgraph-hitl-node` | Adding or modifying `LangGraph` state, nodes, `interrupt()` / `Command(resume=...)`, checkpointer lifecycle, SSE event streaming, or idempotent commit ledger | `AGENTS.md`, `IMPLEMENTATION_PLAN.md`, `backend/src/hitl_workbench/` | `cd backend && uv run ruff check . && uv run pytest -q` |
| `flutter-workbench-ui` | Building or refactoring Flutter pages, `BaseViewModel` / `UiState`, 3-pane desktop/web review layout, mobile layout, or client replay/API wiring | `AGENTS.md`, `app/lib/core/`, adjacent `app/lib/` features | `cd app && dart analyze lib/ && flutter test` |
| `trace-to-eval-export` | Working on human-correction diff capture, `regression_cases.jsonl` export schema, or offline evaluation replay scripts | `IMPLEMENTATION_PLAN.md`, `backend/src/hitl_workbench/` | `cd backend && uv run pytest -q` |
| `verify-before-done` | Finishing any implementation phase or preparing a phase-gate report | `AGENTS.md`, `IMPLEMENTATION_PLAN.md` | Both `backend` and `app` validation commands |
