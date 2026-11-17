---
name: verify-before-done
description: Use before concluding any implementation phase or reporting phase-gate completion in agent-hitl-workbench. Covers mandatory lint, type/static analysis, test execution, and honest reporting of unverified surfaces.
---

# Verify Before Done Gate

## Workflow

1. Run backend checks: `cd backend && uv run ruff check . && uv run pytest -q`.
2. Run Flutter checks: `cd app && dart analyze lib/ && flutter test`.
3. If Web compatibility or UI changed, verify `cd app && flutter build web`.
4. Check `git status` to ensure zero secrets, `.db` files, or unrelated artifacts are staged or untracked in tracked paths.
5. Report exact commands run, pass/fail counts, and any unverified surface; stop at the human review gate without auto-committing.
