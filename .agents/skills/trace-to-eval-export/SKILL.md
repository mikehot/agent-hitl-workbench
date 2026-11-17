---
name: trace-to-eval-export
description: Use when implementing or updating human-correction diff capture, regression_cases.jsonl export schema, or offline evaluation replay runners in backend/. Do not use for unrelated UI styling.
---

# Trace-to-Eval Flywheel Workflow

## Before You Start

- Read `IMPLEMENTATION_PLAN.md` for the `EvalRegressionCase` schema contract.

## Workflow

1. When a human reviewer edits one or more extracted fields during `Command(resume=...)` and approves, compute field-level diffs (`field_name`, `raw_value`, `corrected_value`).
2. Persist and expose each approved correction as a deterministic JSONL record (`case_id`, `thread_id`, `doc_type`, `guard_flags`, `raw_extraction`, `expected_truth`, `created_at`).
3. Keep offline replay scoring deterministic and report honest sample sizes without extrapolating population error rates.

## Validation

- `cd backend && uv run ruff check . && uv run pytest -q`

## Do Not

- Do not silently overwrite or mutate pre-registered baseline datasets when appending human-reviewed cases.
